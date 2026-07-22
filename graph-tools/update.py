import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import ROOT, OUT, drop_noise_nodes, clean_repo_stat_caches, name_communities, communities_from_graph


def main():
    from graphify.detect import detect_incremental, save_manifest
    from graphify.extract import extract
    from graphify.build import build_merge
    from graphify.export import to_json

    if not (OUT / 'manifest.json').exists():
        raise SystemExit('ERROR: no manifest, run graph-tools\\rebuild-graph.ps1 first')

    inc = detect_incremental(Path(str(ROOT)))
    clean_repo_stat_caches()
    new_files = inc.get('new_files', {})
    deleted = list(inc.get('deleted_files', []))
    # manifest can list ignore-excluded files as deleted, a file still on disk is not a deletion
    deleted = [f for f in deleted if not (ROOT / f).exists() and not Path(f).exists()]
    changed_code = [Path(f) for f in new_files.get('code', [])]
    skipped = [f for t, fs in new_files.items() if t != 'code' for f in fs]
    if not changed_code and not deleted:
        print('up to date, nothing changed')
        if skipped:
            print(f'{len(skipped)} doc/image changes skipped (semantic; run a full /graphify session)')
        if '--cluster' in sys.argv:
            recluster()
        return
    if skipped:
        print(f'{len(skipped)} doc/image changes skipped (semantic; run a full /graphify session)')
    print(f'{len(changed_code)} changed code files, {len(deleted)} deleted')

    if changed_code:
        extraction = extract(changed_code, cache_root=Path(str(ROOT)))
    else:
        extraction = {'nodes': [], 'edges': [], 'hyperedges': [],
                      'input_tokens': 0, 'output_tokens': 0}
    extraction = drop_noise_nodes(extraction)

    graph_path = OUT / 'graph.json'
    shutil.copy(graph_path, OUT / '.graphify_old.json')
    G = build_merge([extraction], graph_path=str(graph_path),
                    prune_sources=deleted or None, root=str(ROOT), directed=True)
    print(f'merged: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges')

    # build_merge doesn't persist, save here
    communities = communities_from_graph(G)
    labels = name_communities(G, communities)

    old_node_count = len(json.loads((OUT / '.graphify_old.json').read_text(encoding='utf-8'))['nodes'])
    # incremental shrink is legit (function removed, file deleted); catastrophic shrink is corruption
    if G.number_of_nodes() < old_node_count * 0.9:
        raise SystemExit(f'ERROR: refusing to write, graph would shrink {old_node_count} -> {G.number_of_nodes()}, run rebuild-graph.ps1 if intentional')
    if not to_json(G, communities, str(graph_path), force=True, community_labels=labels):
        raise SystemExit('ERROR: to_json refused to write')

    save_manifest(inc['files'], root=str(ROOT))

    old = json.loads((OUT / '.graphify_old.json').read_text(encoding='utf-8'))
    old_n = len(old['nodes'])
    old_e = len(old.get('links', old.get('edges', [])))
    print(f'diff: nodes {old_n} -> {G.number_of_nodes()}, edges {old_e} -> {G.number_of_edges()}')
    (OUT / '.graphify_old.json').unlink()

    if '--cluster' in sys.argv:
        recluster()


def recluster():
    from graphify.build import build_from_json
    from graphify.cluster import cluster, score_all
    from graphify.analyze import god_nodes, surprising_connections, suggest_questions
    from graphify.report import generate
    from graphify.export import to_json

    g = json.loads((OUT / 'graph.json').read_text(encoding='utf-8'))
    edges = g.get('links', g.get('edges', []))
    extraction = {'nodes': g['nodes'], 'edges': edges,
                  'hyperedges': g.get('hyperedges', []),
                  'input_tokens': 0, 'output_tokens': 0}
    G = build_from_json(extraction, root=str(ROOT), directed=True)
    communities = cluster(G)
    cohesion = score_all(G, communities)
    labels = name_communities(G, communities)
    detection = {'files': {}, 'total_files': len(g['nodes']), 'total_words': 0,
                 'skipped_sensitive': []}
    gods = god_nodes(G)
    surprises = surprising_connections(G, communities)
    questions = suggest_questions(G, communities, labels)
    report = generate(G, communities, cohesion, labels, gods, surprises, detection,
                      {'input': 0, 'output': 0}, str(ROOT), suggested_questions=questions)
    (OUT / 'GRAPH_REPORT.md').write_text(report, encoding='utf-8')
    graph_path = OUT / 'graph.json'
    # node count never changes on recluster, guard passes naturally; refusal means something's broken
    if not to_json(G, communities, str(graph_path), force=False, community_labels=labels):
        raise SystemExit('ERROR: recluster write refused')
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
    print(f'reclustered: {len(communities)} communities, report regenerated')


if __name__ == '__main__':
    main()
