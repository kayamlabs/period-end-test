#!/usr/bin/env bash
# Period-end test: run one model on Corner Shop twice, with and without the episode length shown.
#
#   ./run.sh <model> [--base-url URL] [--api-key-var VAR] [--out DIR] [-n FIRMS] [-c CONCURRENCY] [--max-tokens N]
#
# Defaults to OpenRouter (key in $OPENROUTER_API_KEY). Point --base-url at any OpenAI-compatible
# endpoint to test your own model or agent. Reasoning models that think inside the token budget may need
# --max-tokens 8000: a reply cut off before its JSON action leaves the week unplayed. Results land in DIR/seen and DIR/hidden; then run
#   python3 compare.py DIR/seen DIR/hidden --label "<model>"
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
model="${1:?usage: ./run.sh <model> [--base-url URL] [--api-key-var VAR] [--out DIR]}"
shift
base_url="https://openrouter.ai/api/v1"
key_var="OPENROUTER_API_KEY"
out="out"
n=10
c=2
max_tokens=2500
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) base_url="$2"; shift 2 ;;
    --api-key-var) key_var="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    -n) n="$2"; shift 2 ;;
    -c) c="$2"; shift 2 ;;
    --max-tokens) max_tokens="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "${!key_var:-}" ]]; then
  echo "set $key_var to your API key first" >&2
  exit 2
fi
vf_run="${VF_RUN:-vf-run}"
command -v "$vf_run" >/dev/null || { echo "vf-run not found: pip install verifiers ./corner-shop/environments/corner_shop (see README)" >&2; exit 2; }

common=(
  -m "$model" -n "$n" -r 1 -c "$c"
  --client.base-url "$base_url" --client.api-key-var "$key_var"
  --client.timeout.read 120 --env.retries.max-retries 2 --env.timeout.episode 1200
  --sampling.max-tokens "$max_tokens" --sampling.reasoning-effort low
  --env.operator.runtime.type subprocess
  --env.taskset.system-prompt "$here/prompts/neutral.txt"
)

mkdir -p "$out"
echo "arm 1/2: end date shown (week X of 13)"
"$vf_run" corner-shop "${common[@]}" -o "$out/seen" > "$out/seen.log" 2>&1 &
seen_pid=$!
echo "arm 2/2: end date hidden (week X)"
"$vf_run" corner-shop "${common[@]}" --env.taskset.hide-horizon true -o "$out/hidden" > "$out/hidden.log" 2>&1 &
hidden_pid=$!
status=0
wait "$seen_pid" || status=1
wait "$hidden_pid" || status=1
grep -h "episodes ok" "$out/seen.log" "$out/hidden.log" || true
[[ $status -eq 0 ]] || { echo "a run failed; see $out/*.log" >&2; exit 1; }
echo "done. next: python3 compare.py $out/seen $out/hidden --label \"$model\""
