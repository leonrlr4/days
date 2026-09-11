#!/usr/bin/env bash
# Tests for scripts/setup's handling of what it writes into bindings.lua.
#
#     tests/run
set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$HERE/../scripts/setup"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

checks=0
failed=0
check() {
  checks=$((checks + 1))
  if [[ "$2" != "$3" ]]; then
    failed=$((failed + 1))
    printf 'FAIL %s\n    expected %s\n    got      %s\n' "$1" "$2" "$3" >&2
  fi
}

fresh() {
  rm -rf "$WORK/cfg"; mkdir -p "$WORK/cfg/hypr" "$WORK/cfg/omarchy"
  printf 'o.bind("SUPER + D", "Dictionary", "x")\n' > "$WORK/cfg/hypr/bindings.lua"
  echo '{"version":1,"plugins":[{"id":"leonrlr4.days"}]}' > "$WORK/cfg/omarchy/shell.json"
}

run() { XDG_CONFIG_HOME="$WORK/cfg" "$SCRIPT" "$@" 2>&1; }

# The key ends up inside a quoted Lua string. Anything that can close that
# string can run whatever it likes the next time Hyprland loads its config.
fresh
out=$(run --key 'SUPER + M", "x", os.execute("touch /tmp/pwned")) --')
check "a key that can close the Lua string is refused" "1" \
  "$(grep -c 'not a valid key' <<<"$out")"
check "and nothing is written" "0" \
  "$(grep -c 'leonrlr4.days' "$WORK/cfg/hypr/bindings.lua")"

fresh
out=$(run --key 'SUPER + M
os.execute("x")')
check "a key containing a newline is refused" "1" "$(grep -c 'not a valid key' <<<"$out")"

fresh
out=$(run --key 'SUPER + \\')
check "a key containing a backslash is refused" "1" "$(grep -c 'not a valid key' <<<"$out")"

# Real keys must still work, including the ones Omarchy itself uses.
for key in "SUPER + M" "SUPER + SHIFT + P" "SUPER + ALT + T" "CTRL + ALT + comma" "SUPER + code:20" "F9"; do
  fresh
  run --key "$key" >/dev/null
  check "a real binding is written: $key" "1" \
    "$(grep -cF "o.bind(\"$key\", \"Daily tasks\"" "$WORK/cfg/hypr/bindings.lua")"
done

if (( failed )); then
  printf 'FAIL %d/%d setup\n' "$failed" "$checks" >&2
  exit 1
fi
printf 'ok  %d checks setup\n' "$checks"
