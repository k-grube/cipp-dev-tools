"""graph query cli, so agents don't hand-roll json scripts

usage:
  python graph-tools/query.py find <text> [more text ...]
  python graph-tools/query.py node <id|label|file>
  python graph-tools/query.py path <from> <to>
  python graph-tools/query.py trace <ApiEndpointName>

find   substring match over label/id/source_file, one line per node
node   resolve one node, print details + every in/out edge
path   shortest directed path (undirected fallback), prints the edge chain
trace  frontend callers -> Invoke-<name> -> forward paths into Craft/ and external_* nodes

path/trace add synthetic in_file hops (function -> its file node) so directed walks
can reach file-level edges like bridge_calls
"""
import json
import sys
from collections import deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import OUT


def load():
    g = json.loads((OUT / 'graph.json').read_text(encoding='utf-8'))
    nodes = {n['id']: n for n in g['nodes']}
    edges = g.get('links', g.get('edges', []))
    out_adj, in_adj = {}, {}
    for e in edges:
        out_adj.setdefault(e['source'], []).append(e)
        in_adj.setdefault(e['target'], []).append(e)
    return nodes, edges, out_adj, in_adj


def add_file_hops(nodes, out_adj):
    # bridge_calls/http_calls edges hang off file nodes, contains points file -> member,
    # so a member node needs a synthetic hop up to its file node for forward walks
    file_of = {}
    for n in nodes.values():
        sf = str(n.get('source_file') or '').replace('\\', '/')
        if sf and str(n.get('label', '')) == Path(sf).name:
            file_of[sf] = n['id']
    hopped = {k: list(v) for k, v in out_adj.items()}
    for n in nodes.values():
        sf = str(n.get('source_file') or '').replace('\\', '/')
        fid = file_of.get(sf)
        if fid and fid != n['id']:
            hopped.setdefault(n['id'], []).append(
                {'source': n['id'], 'target': fid, 'relation': 'in_file'})
    return hopped


def fmt(n):
    sf = str(n.get('source_file') or '').replace('\\', '/')
    return f"{n['id']}  |  {n.get('label', '')}  |  {sf}"


def matches(n, terms):
    hay = ' '.join([str(n['id']), str(n.get('label', '')),
                    str(n.get('source_file') or '')]).lower().replace('\\', '/')
    return all(t.lower() in hay for t in terms)


def resolve(nodes, query):
    q = query.lower()
    if query in nodes:
        return nodes[query]
    exact = [n for n in nodes.values() if str(n.get('label', '')).lower() in (q, q + '()', '.' + q + '()')]
    if len(exact) == 1:
        return exact[0]
    cands = exact or [n for n in nodes.values() if matches(n, [query])]
    if len(cands) == 1:
        return cands[0]
    if not cands:
        sys.exit(f"no node matches '{query}' (try: find {query})")
    print(f"'{query}' is ambiguous ({len(cands)} matches), pick an id:")
    for n in cands[:20]:
        print(' ', fmt(n))
    sys.exit(2)


def cmd_find(argv):
    nodes, *_ = load()
    hits = [n for n in nodes.values() if matches(n, argv)]
    for n in hits[:50]:
        print(fmt(n))
    print(f'{len(hits)} matches' + (' (first 50 shown)' if len(hits) > 50 else ''))


def cmd_node(argv):
    nodes, _, out_adj, in_adj = load()
    n = resolve(nodes, ' '.join(argv))
    print(fmt(n))
    print(f"community: {n.get('community', '?')}")
    for e in in_adj.get(n['id'], []):
        src = nodes.get(e['source'], {})
        print(f"  <- {e.get('relation', '?')} <- {src.get('label', e['source'])}  ({str(src.get('source_file') or '').replace(chr(92), '/')})")
    for e in out_adj.get(n['id'], []):
        dst = nodes.get(e['target'], {})
        print(f"  -> {e.get('relation', '?')} -> {dst.get('label', e['target'])}  ({str(dst.get('source_file') or '').replace(chr(92), '/')})")


def bfs(start, goals, out_adj, undirected_in=None):
    # goals: set of node ids, returns edge list of shortest path to nearest goal
    prev = {start: None}
    q = deque([start])
    while q:
        cur = q.popleft()
        if cur in goals and cur != start:
            path = []
            while prev[cur]:
                path.append(prev[cur])
                cur = prev[cur]['source'] if prev[cur]['target'] == cur else prev[cur]['target']
            return list(reversed(path))
        for e in out_adj.get(cur, []):
            if e['target'] not in prev:
                prev[e['target']] = e
                q.append(e['target'])
        for e in (undirected_in.get(cur, []) if undirected_in else []):
            if e['source'] not in prev:
                prev[e['source']] = e
                q.append(e['source'])
    return None


def print_path(path, nodes, start_id):
    cur = start_id
    print(fmt(nodes[cur]))
    for e in path:
        nxt = e['target'] if e['source'] == cur else e['source']
        arrow = '->' if e['source'] == cur else '<-'
        print(f"  {arrow} {e.get('relation', '?')} {arrow} {fmt(nodes[nxt])}")
        cur = nxt


def cmd_path(argv):
    if len(argv) < 2:
        sys.exit('usage: path <from> <to>')
    nodes, _, out_adj, in_adj = load()
    a = resolve(nodes, argv[0])
    b = resolve(nodes, ' '.join(argv[1:]))
    out_adj = add_file_hops(nodes, out_adj)
    path = bfs(a['id'], {b['id']}, out_adj)
    if path is None:
        path = bfs(a['id'], {b['id']}, out_adj, undirected_in=in_adj)
        if path is None:
            sys.exit(f"no path between {a['id']} and {b['id']}")
        print('(no directed path, undirected shown)')
    print_path(path, nodes, a['id'])


def cmd_trace(argv):
    name = argv[0]
    nodes, _, out_adj, in_adj = load()
    want = f'invoke-{name}()'.lower()
    fn = next((n for n in nodes.values() if str(n.get('label', '')).lower() == want), None)
    if fn is None:
        sys.exit(f"no Invoke-{name} node (try: find {name})")
    print(f'== {fn.get("label")} ({str(fn.get("source_file")).replace(chr(92), "/")})')
    callers = [e for e in in_adj.get(fn['id'], []) if e.get('relation') == 'http_calls']
    print(f'-- frontend callers ({len(callers)}):')
    for e in callers[:15]:
        print('  ', fmt(nodes.get(e['source'], {'id': e['source']})))
    if len(callers) > 15:
        print(f'   ... {len(callers) - 15} more')
    goals = {nid for nid, n in nodes.items()
             if str(n.get('type', '')) == 'external_api'
             or str(n.get('source_file') or '').replace('\\', '/').startswith('Craft/')}
    path = bfs(fn['id'], goals, add_file_hops(nodes, out_adj))
    print('-- forward path into craft/microsoft:')
    if path is None:
        print('   none reachable (this endpoint may not touch the craft bridge directly)')
    else:
        print_path(path, nodes, fn['id'])


def main():
    cmds = {'find': cmd_find, 'node': cmd_node, 'path': cmd_path, 'trace': cmd_trace}
    if len(sys.argv) < 3 or sys.argv[1] not in cmds:
        sys.exit(__doc__.strip())
    cmds[sys.argv[1]](sys.argv[2:])


if __name__ == '__main__':
    main()
