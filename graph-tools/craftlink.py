import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import ROOT, OUT, name_communities, communities_from_graph
from routelink import scan_routes

# synthetic source_file, same mechanism as route-links (build_merge replaces per source_file)
CRAFT_SOURCE = 'graph-tools/craft-links'
# backend ps1 -> craft C# static bridge, e.g. [Craft.Services.OrchestratorBridge]::QueueOrchestration(...)
BRIDGE_RE = re.compile(r'\[Craft\.Services\.([A-Za-z0-9_]+)\]::([A-Za-z0-9_]+)')
# microsoft-facing hosts in craft source (token endpoints, graph, arm)
MS_HOST_RE = re.compile(
    r'https://([a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:microsoft|microsoftonline|azure|windows)\.(?:com|net|us))', re.I)
# /api/ routes craft serves itself (auth, setup wizard), /API/{endpoint} dispatch template won't match
CRAFT_ROUTE_RE = re.compile(r'Map(?:Get|Post|Put|Delete|Methods)\(\s*"/(?:api|API)/([A-Za-z][A-Za-z0-9_]*)')


def read_text(f):
    try:
        return f.read_text(encoding='utf-8', errors='ignore')
    except OSError:
        return ''


def scan_bridge_calls():
    calls = {}
    src = ROOT / 'CIPP' / 'backend'
    for f in src.rglob('*'):
        if f.suffix.lower() not in ('.ps1', '.psm1'):
            continue
        found = set(BRIDGE_RE.findall(read_text(f)))
        if found:
            calls[f.relative_to(ROOT).as_posix()] = found
    return calls


def scan_ms_calls():
    hosts = {}
    src = ROOT / 'Craft'
    for f in src.rglob('*'):
        if f.suffix.lower() not in ('.cs', '.ps1'):
            continue
        rel = f.relative_to(ROOT).as_posix()
        if rel.startswith('Craft/perf-harness'):
            continue
        found = set()
        for line in read_text(f).splitlines():
            s = line.strip()
            # doc comments and html help links are not calls
            if s.startswith(('//', '#', '*')) or 'href=' in s:
                continue
            found.update(h.lower() for h in MS_HOST_RE.findall(line))
        if found:
            hosts[rel] = found
    return hosts


def scan_craft_routes():
    prog = ROOT / 'Craft' / 'Services' / 'Program.cs'
    if not prog.exists():
        return {}
    return {name.lower() for name in CRAFT_ROUTE_RE.findall(read_text(prog))}


def build_fragment(graph):
    nodes = graph['nodes']
    file_nodes = {}    # rel path -> node id (label == basename)
    class_nodes = {}   # craft class label -> (id, source_file)
    method_nodes = {}  # (craft source_file, '.Method()') -> id
    invoke_names = set()
    for n in nodes:
        sf = (n.get('source_file') or '').replace('\\', '/')
        label = str(n.get('label', ''))
        if label == Path(sf).name:
            file_nodes[sf] = n['id']
        if sf.startswith('Craft/'):
            if label.startswith('.') and label.endswith('()'):
                method_nodes[(sf, label)] = n['id']
            elif label and label != Path(sf).name:
                class_nodes.setdefault(label, (n['id'], sf))
        if label.lower().startswith('invoke-') and label.endswith('()'):
            invoke_names.add(label[len('invoke-'):-2].lower())

    edges = []
    orphans = []
    ext_nodes = {}

    def add_edge(src_id, dst_id, relation, location):
        edges.append({
            'source': src_id, 'target': dst_id,
            'relation': relation,
            'confidence': 'EXTRACTED', 'confidence_score': 1.0,
            'source_file': CRAFT_SOURCE,
            'source_location': location, 'weight': 1.0,
        })

    # backend -> craft bridge calls
    for be_file, refs in scan_bridge_calls().items():
        be_id = file_nodes.get(be_file)
        for cls, meth in sorted(refs):
            cls_node = class_nodes.get(cls)
            target = None
            if cls_node:
                target = method_nodes.get((cls_node[1], f'.{meth}()')) or cls_node[0]
            if be_id and target:
                add_edge(be_id, target, 'bridge_calls', be_file)
            else:
                orphans.append({'file': be_file, 'ref': f'{cls}::{meth}',
                                'missing': 'backend node' if not be_id else 'craft node'})

    # craft -> microsoft endpoints (synthetic external nodes)
    for craft_file, hosts in scan_ms_calls().items():
        cf_id = file_nodes.get(craft_file)
        if not cf_id:
            orphans.append({'file': craft_file, 'ref': ','.join(sorted(hosts)),
                            'missing': 'craft node'})
            continue
        for host in sorted(hosts):
            hid = 'external_' + re.sub(r'[^a-z0-9]', '_', host)
            ext_nodes.setdefault(hid, {
                'id': hid, 'label': host, 'type': 'external_api',
                'source_file': CRAFT_SOURCE,
            })
            add_edge(cf_id, hid, 'http_calls', craft_file)

    # frontend -> craft-served /api routes (auth/setup), backend Invoke-* wins on collision
    craft_routes = scan_craft_routes()
    prog_id = file_nodes.get('Craft/Services/Program.cs')
    if craft_routes and prog_id:
        for fe_file, names in scan_routes().items():
            fe_id = file_nodes.get(fe_file)
            for name in sorted(names):
                if name.lower() in craft_routes and name.lower() not in invoke_names:
                    if fe_id:
                        add_edge(fe_id, prog_id, 'http_calls', fe_file)
                    else:
                        orphans.append({'file': fe_file, 'ref': name,
                                        'missing': 'frontend node'})

    fragment = {'nodes': list(ext_nodes.values()), 'edges': edges, 'hyperedges': [],
                'input_tokens': 0, 'output_tokens': 0}
    return fragment, orphans


def inject(directed=True):
    from graphify.build import build_merge
    from graphify.export import to_json
    graph = json.loads((OUT / 'graph.json').read_text(encoding='utf-8'))
    if not any(str(n.get('source_file', '')).replace('\\', '/').startswith('Craft/')
               for n in graph['nodes']):
        print('craft pass: no Craft/ nodes in graph, run graph-tools\\rebuild-graph.ps1 after cloning Craft (setup.ps1)')
        return
    fragment, orphans = build_fragment(graph)
    (OUT / 'craft-orphans.json').write_text(json.dumps(orphans, indent=2), encoding='utf-8')
    if not fragment['edges']:
        print('craft pass: 0 edges resolved, skipping merge')
        return
    G = build_merge([fragment], graph_path=str(OUT / 'graph.json'),
                    root=str(ROOT), directed=directed)
    # build_merge doesn't persist, reuse stored community attrs, re-clustering is opt-in elsewhere
    communities = communities_from_graph(G)
    labels = name_communities(G, communities)
    # force=True behind a 10% bound: dropped external nodes and build_merge fuzzy dedup
    # legitimately shrink the graph by a few nodes, the #479 guard would silently refuse
    if G.number_of_nodes() < len(graph['nodes']) * 0.9:
        raise SystemExit(f'ERROR: craft pass would shrink {len(graph["nodes"])} -> {G.number_of_nodes()} nodes, refusing')
    if not to_json(G, communities, str(OUT / 'graph.json'), force=True, community_labels=labels):
        raise SystemExit('ERROR: craft pass write refused')
    print(f'craft pass: {len(fragment["edges"])} edges ({len(fragment["nodes"])} external nodes), '
          f'{len(orphans)} orphans, graph now {G.number_of_nodes()} nodes / {G.number_of_edges()} edges')


if __name__ == '__main__':
    inject()
