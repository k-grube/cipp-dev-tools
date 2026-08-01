#!/usr/bin/env bash
# forwards to frontend-tests npm scripts: ./test.sh [--watch|--unit|--storybook|--browser|--coverage] [vitest args]
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
script=test
rest=()
for a in "$@"; do
    case "$a" in
        --watch|-w) script=test:watch ;;
        --unit|-u) script=test:unit ;;
        --storybook|-s) script=test:storybook ;;
        --browser|-b) script=test:browser ;;
        --coverage|-c) script=test:coverage ;;
        --help|-h)
            echo 'usage: ./test.sh [--watch|--unit|--storybook|--browser|--coverage] [vitest args, e.g. a test file or -t "name"]'
            echo 'default (no flag): both projects (unit jsdom + storybook chromium)'
            exit 0 ;;
        *) rest+=("$a") ;;
    esac
done
cd "$root/frontend-tests"
if [ "${#rest[@]}" -gt 0 ]; then
    exec npm run "$script" -- "${rest[@]}"
else
    exec npm run "$script"
fi
