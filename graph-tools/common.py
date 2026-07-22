import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'graphify-out'

# docs excluded from semantic scope (lean run, spec section "out of scope")
DOC_EXCLUDE_SUBSTRINGS = (
    'CIPPTests',
    'LICENSE', 'license.md', 'CLA.md',
    'words.txt', 'robots.txt', 'version_latest.txt',
    'CHANGELOG.md', 'about_ModuleBuilder',
    '.redocly.lint-ignore',
)

# node-label prefixes that are json-schema artifacts, not entities
NOISE_LABEL_PREFIXES = ('$defs', '$schema', '$ref')


def lean_docs(files):
    docs = files.get('document', [])
    return [f for f in docs if not any(s in f for s in DOC_EXCLUDE_SUBSTRINGS)]


def drop_noise_nodes(extraction):
    noisy = {n['id'] for n in extraction['nodes']
             if str(n.get('label', '')).startswith(NOISE_LABEL_PREFIXES)}
    if not noisy:
        return extraction
    extraction['nodes'] = [n for n in extraction['nodes'] if n['id'] not in noisy]
    extraction['edges'] = [e for e in extraction['edges']
                           if e['source'] not in noisy and e['target'] not in noisy]
    print(f'noise filter: dropped {len(noisy)} nodes')
    return extraction


def clean_repo_stat_caches():
    # detect writes stat caches into the scan root, keep repos clean
    for repo in ('cipp',):
        stray = ROOT / repo / 'graphify-out'
        if stray.exists():
            shutil.rmtree(stray)


def communities_from_graph(G):
    # rebuild the communities dict from per-node community attrs, -1 for unassigned
    communities = {}
    for n, d in G.nodes(data=True):
        cid = d.get('community', -1)
        try:
            cid = int(cid)
        except (TypeError, ValueError):
            cid = -1
        communities.setdefault(cid, []).append(n)
    return communities


def name_communities(G, communities):
    labels = {}
    for cid, members in communities.items():
        best = max(members, key=lambda n: G.degree(n) if n in G else 0)
        label = G.nodes[best].get('label', best) if best in G else str(best)
        labels[int(cid)] = f'{label} cluster'
    return labels
