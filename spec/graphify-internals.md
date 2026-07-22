# graphify 0.9.12 internals the toolkit depends on

pin is exact (`graphifyy==0.9.12`). before bumping, re-verify each:

- ignore matching uses python fnmatch: `*` crosses `/`. root-anchored patterns (leading `/`) fnmatch against the scan-root-relative path as a full string; unanchored patterns match every path component at every depth (why all our entries are anchored)
- detect merges the scan root's own `.gitignore` into the ignore set: this workspace's `cipp/` gitignore line would collapse the corpus to nothing, so `.graphifyignore` carries an unanchored `!cipp` negation (last-match-wins) before the anchored excludes. keep that line
- nested `.gitignore` / `.graphifyignore` inside subdirectories are NOT read when scanning from a parent root (`_load_graphifyignore` walks upward only). our committed `.graphifyignore` is the single scope authority
- `build_merge` does NOT persist to disk (docstring claims otherwise). every caller must to_json afterward
- `build_merge` replace-on-re-extract: all base-graph nodes/edges whose `source_file` matches any incoming one are dropped before merge. this is why route edges use the synthetic `graph-tools/route-links` source
- `to_json(G, communities, path, force=, community_labels=)` returns False (writing nothing) when the new graph has fewer nodes than the existing file unless force=True (#479). update.py wraps this with its own 10 percent threshold + force=True; routelink/recluster use force=False deliberately
- `python -m graphify export html` reads community groupings from `.graphify_analysis.json` and labels from `.graphify_labels.json` - both must be regenerated whenever clustering changes (rebuild.py and update.py --cluster do)
- `graphify.extract.extract` uses multiprocessing: any calling script needs `if __name__ == '__main__':` on windows
- detect writes `graphify-out/cache/stat-index.json` into the scan root
- zero-node source files are reported and retried each run (#1666), the warning is benign
