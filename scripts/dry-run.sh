#!/usr/bin/env bash
# Read-only Renovate lookup dry run plus lane report. Writes nothing to GitLab.
#
#   scripts/dry-run.sh gitlab <out-dir> homelab/<repo> [homelab/<repo> ...]
#       The repos as they are on GitLab now (their main, the presets on this
#       project's main).
#   scripts/dry-run.sh local <out-dir> <path to a repo checkout>
#       That working tree, uncommitted changes included, against THIS
#       checkout's presets: they are served over loopback HTTP and the clone's
#       local>example-org/renovate extends are pointed there. Use it before
#       committing a preset or a repo's renovate.json.
#
# Writes <out-dir>/dry-run.ndjson (debug log) and <out-dir>/lanes.tsv.
# Tokens: the glab login for source.example.com (RENOVATE_TOKEN) and, if
# present, the gh login (GITHUB_COM_TOKEN, avoids the 60/h github.com limit).
# Neither is printed or passed on the command line.
set -euo pipefail

mode=${1:?usage: dry-run.sh gitlab|local <out-dir> <repos...|repo-dir>}
out=${2:?out-dir}
shift 2
here=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$out"
out=$(cd "$out" && pwd)

RENOVATE_TOKEN=$(glab config get token --host source.example.com 2>/dev/null || true)
[ -n "$RENOVATE_TOKEN" ] || { echo "no glab login for source.example.com" >&2; exit 1; }
export RENOVATE_TOKEN
GITHUB_COM_TOKEN=$(gh auth token 2>/dev/null || true)
[ -n "$GITHUB_COM_TOKEN" ] && export GITHUB_COM_TOKEN
export LOG_LEVEL=debug LOG_FORMAT=json
hosts='{"matchHost":"https://registry.example.com","allowInternal":true},{"matchHost":"https://source.example.com","allowInternal":true}'

case "$mode" in
  gitlab)
    [ "$#" -gt 0 ] || { echo "name at least one homelab/<repo>" >&2; exit 2; }
    RENOVATE_HOST_RULES="[$hosts]" renovate --platform=gitlab \
      --endpoint=https://source.example.com/api/v4/ --dry-run=lookup \
      --onboarding=false --require-config=optional "$@" >"$out/dry-run.ndjson" 2>&1 || true
    ;;
  local)
    src=$(cd "${1:?repo-dir}" && pwd)
    port=${PRESET_PORT:-8765}
    python3 -m http.server "$port" --bind 127.0.0.1 --directory "$here" >/dev/null 2>&1 &
    server=$!
    trap 'kill "$server" 2>/dev/null || true' EXIT
    clone="$out/clone"
    rm -rf "$clone"
    git clone -q "$src" "$clone"
    # Carry the working tree's uncommitted changes into the clone.
    (cd "$src" && git diff --name-only HEAD) | while read -r f; do
      if [ -e "$src/$f" ]; then mkdir -p "$clone/$(dirname "$f")"; cp "$src/$f" "$clone/$f"; else rm -f "$clone/$f"; fi
    done
    sed -i.bak -E "s#\"local>example-org/renovate:([a-z-]+)#\"http://127.0.0.1:$port/\1.json#g; s#\"local>example-org/renovate\"#\"http://127.0.0.1:$port/default.json\"#g" "$clone/renovate.json"
    rm -f "$clone/renovate.json.bak"
    sleep 1
    (cd "$clone" && RENOVATE_HOST_RULES="[{\"matchHost\":\"http://127.0.0.1:$port\",\"allowInternal\":true},$hosts]" \
      renovate --platform=local --dry-run=lookup --onboarding=false >"$out/dry-run.ndjson" 2>&1) || true
    ;;
  *)
    echo "mode must be gitlab or local" >&2
    exit 2
    ;;
esac

echo "warnings and errors:"
grep '"level":[45]0' "$out/dry-run.ndjson" \
  | python3 -c 'import sys,json
for l in sys.stdin:
    e=json.loads(l); err=e.get("err") or {}
    print(" ", e.get("repository","-"), "|", e.get("msg"), err.get("validationError",""))' \
  | grep -v 'RE2 not usable' | sort | uniq -c || true
# The engine prints a harmless "logger has not yet been initialized" note when
# imported outside a run.
node "$here/scripts/lane-report.mjs" "$out/dry-run.ndjson" >"$out/lanes.tsv" 2> >(grep -v "logger has not" >&2)
echo "lane report: $out/lanes.tsv ($(($(wc -l <"$out/lanes.tsv") - 1)) rows)"
