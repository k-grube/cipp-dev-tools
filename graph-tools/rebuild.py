import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import ROOT, OUT, lean_docs, drop_noise_nodes, clean_repo_stat_caches, name_communities


def main():
    from graphify.detect import detect, save_manifest
    from graphify.extract import extract, collect_files
    from graphify.cache import check_semantic_cache
    from graphify.build import build_from_json
    from graphify.cluster import cluster, score_all
    from graphify.analyze import god_nodes, surprising_connections, suggest_questions
    from graphify.report import generate
    from graphify.export import to_json

    detection = detect(Path(str(ROOT)))
    clean_repo_stat_caches()
    code_files = [Path(f) for f in detection['files'].get('code', [])]
    print(f'detect: {detection["total_files"]} files, {len(code_files)} code')

    ast = extract(code_files, cache_root=Path(str(ROOT)))

    docs = lean_docs(detection['files'])
    cn, ce, ch, uncached = check_semantic_cache(docs, root=str(ROOT))
    if uncached:
        print(f'semantic: {len(uncached)} docs uncached, skipped (run a full /graphify session to add them)')
    print(f'semantic: {len(docs) - len(uncached)} docs from cache')

    seen = {n['id'] for n in ast['nodes']}
    nodes = list(ast['nodes']) + [n for n in cn if n['id'] not in seen]
    extraction = {'nodes': nodes, 'edges': ast['edges'] + ce, 'hyperedges': ch,
                  'input_tokens': 0, 'output_tokens': 0}
    extraction = drop_noise_nodes(extraction)

    G = build_from_json(extraction, root=str(ROOT), directed=True)
    if G.number_of_nodes() == 0:
        raise SystemExit('ERROR: empty graph, aborting before any write')
    communities = cluster(G)
    cohesion = score_all(G, communities)
    labels = name_communities(G, communities)
    gods = god_nodes(G)
    surprises = surprising_connections(G, communities)
    questions = suggest_questions(G, communities, labels)

    # intentional shrink vs old undirected graph, back up then force overwrite past the #479 guard
    graph_path = OUT / 'graph.json'
    if graph_path.exists():
        shutil.copy(graph_path, OUT / 'graph.json.bak')
    if not to_json(G, communities, str(graph_path), force=True, community_labels=labels):
        raise SystemExit('ERROR: to_json refused to write')

    report = generate(G, communities, cohesion, labels, gods, surprises,
                      detection, {'input': 0, 'output': 0}, str(ROOT),
                      suggested_questions=questions)
    (OUT / 'GRAPH_REPORT.md').write_text(report, encoding='utf-8')
    (OUT / '.graphify_labels.json').write_text(
        json.dumps({str(k): v for k, v in labels.items()}), encoding='utf-8')
    analysis = {
        'communities': {str(k): v for k, v in communities.items()},
        'cohesion': {str(k): v for k, v in cohesion.items()},
        'gods': gods,
        'surprises': surprises,
        'questions': questions,
    }
    (OUT / '.graphify_analysis.json').write_text(json.dumps(analysis), encoding='utf-8')
    save_manifest(detection['files'], root=str(ROOT))
    print(f'rebuild: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges, '
          f'{len(communities)} communities (directed)')


if __name__ == '__main__':
    main()
