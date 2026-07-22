import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import ROOT, OUT, name_communities, communities_from_graph

ROUTE_SOURCE = 'graph-tools/route-links'
ROUTE_RE = re.compile(r'/api/([A-Za-z][A-Za-z0-9_]*)')


def scan_routes():
    routes = {}
    src = ROOT / 'cipp' / 'frontend' / 'src'
    for f in src.rglob('*'):
        if f.suffix.lower() not in ('.js', '.jsx', '.json'):
            continue
        try:
            text = f.read_text(encoding='utf-8', errors='ignore')
        except OSError:
            continue
        names = set(ROUTE_RE.findall(text))
        if names:
            routes[f.relative_to(ROOT).as_posix()] = names
    return routes


def build_fragment(graph):
    nodes = graph['nodes']
    # file node per frontend file: label == basename, source_file == rel path
    file_nodes = {}
    invoke_nodes = {}
    for n in nodes:
        sf = (n.get('source_file') or '').replace('\\', '/')
        label = n.get('label', '')
        if sf.startswith('cipp/frontend/src') and label == Path(sf).name:
            file_nodes[sf] = n['id']
        if label.lower().startswith('invoke-') and label.endswith('()'):
            # prefer http entrypoints on name collision
            key = label[len('invoke-'):-2].lower()
            if key not in invoke_nodes or 'CIPPHTTP' in sf:
                invoke_nodes[key] = n['id']

    edges = []
    orphans = []
    for fe_file, names in scan_routes().items():
        fe_id = file_nodes.get(fe_file)
        for name in sorted(names):
            be_id = invoke_nodes.get(name.lower())
            if fe_id and be_id:
                edges.append({
                    'source': fe_id, 'target': be_id,
                    'relation': 'http_calls',
                    'confidence': 'EXTRACTED', 'confidence_score': 1.0,
                    'source_file': ROUTE_SOURCE,
                    'source_location': fe_file, 'weight': 1.0,
                })
            else:
                orphans.append({'file': fe_file, 'route': name,
                                'missing': 'frontend node' if not fe_id else 'backend node'})
    fragment = {'nodes': [], 'edges': edges, 'hyperedges': [],
                'input_tokens': 0, 'output_tokens': 0}
    return fragment, orphans


def inject(directed=True):
    from graphify.build import build_merge
    from graphify.export import to_json
    graph = json.loads((OUT / 'graph.json').read_text(encoding='utf-8'))
    fragment, orphans = build_fragment(graph)
    (OUT / 'route-orphans.json').write_text(json.dumps(orphans, indent=2), encoding='utf-8')
    if not fragment['edges']:
        print('route pass: 0 edges resolved, skipping merge')
        return
    G = build_merge([fragment], graph_path=str(OUT / 'graph.json'),
                    root=str(ROOT), directed=directed)
    # build_merge doesn't persist, reuse stored community attrs, re-clustering is opt-in elsewhere
    communities = communities_from_graph(G)
    labels = name_communities(G, communities)
    to_json(G, communities, str(OUT / 'graph.json'), force=False, community_labels=labels)
    print(f'route pass: {len(fragment["edges"])} edges, {len(orphans)} orphans, '
          f'graph now {G.number_of_nodes()} nodes / {G.number_of_edges()} edges')


if __name__ == '__main__':
    inject()
