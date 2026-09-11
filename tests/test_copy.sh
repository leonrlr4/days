#!/usr/bin/env bash
# Tests for scripts/copy-image, and for the interpreter every script starts with.
#
#     tests/run
#
# The happy path puts a real image on the real clipboard, so it only runs when
# DAYS_TEST_CLIPBOARD=1 asks for it.
set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPTS="$HERE/../scripts"
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

# --- the interpreter --------------------------------------------------------
# A script's own PATH is exported by its first line of body, which is far too
# late: #!/usr/bin/env bash resolves bash through the ambient PATH before any
# of that runs, so a shadowed bash executes the whole script. Verified by
# shadowing one on this machine.
for f in "$SCRIPTS"/*; do
  [[ -f $f ]] || continue
  check "$(basename "$f") starts with an absolute interpreter" "1" \
    "$(head -1 "$f" | grep -c '^#!/usr/bin/bash$')"
done

# --- copy-image -------------------------------------------------------------
D="$WORK/store"; mkdir -p "$D/blobs"
magick -size 120x90 gradient:red-blue "$WORK/real.png"
SHA=$(sha256sum "$WORK/real.png" | cut -d' ' -f1)
cp "$WORK/real.png" "$D/blobs/$SHA.png"

run() { "$SCRIPTS/copy-image" --dir "$D" "$@" 2>/dev/null; }

check "a short hash is refused" "1" \
  "$(run --sha aa11aa11 --ext png | grep -c 'content hash')"
check "a non-hex hash is refused" "1" \
  "$(run --sha "$(printf 'z%.0s' {1..64})" --ext png | grep -c 'content hash')"
check "a path is refused" "1" \
  "$(run --sha ../../etc/passwd --ext png | grep -c 'content hash')"
check "an unknown extension is refused" "1" \
  "$(run --sha "$SHA" --ext exe | grep -c 'unsupported')"
check "a hash with no stored image is refused" "false" \
  "$(run --sha "$(printf 'a%.0s' {1..64})" --ext png | jq -r .ok)"

# The blobs are content-addressed, so the name is a claim about the bytes.
# Checking the bytes through the descriptor that will be read is what makes a
# swap between the check and the read impossible: whatever reaches the
# clipboard has been proven to hash to the name that was asked for.
WRONG=$(printf 'b%.0s' {1..64})
cp "$WORK/real.png" "$D/blobs/$WRONG.png"
printf 'not the image you asked for\n' >> "$D/blobs/$WRONG.png"
out=$(run --sha "$WRONG" --ext png)
check "a blob whose bytes do not match its name is refused" "false" "$(jq -r .ok <<<"$out")"
check "and it says why" "1" "$(jq -r '.error // ""' <<<"$out" | grep -ci 'match\|identity\|hash')"

# A symlink standing where the blob should be must not be read through.
LINK=$(printf 'c%.0s' {1..64})
printf 'secret\n' > "$WORK/elsewhere.txt"
ln -s "$WORK/elsewhere.txt" "$D/blobs/$LINK.png"
check "a symlinked blob is refused" "false" "$(run --sha "$LINK" --ext png | jq -r .ok)"

if [[ "${DAYS_TEST_CLIPBOARD:-0}" == "1" ]]; then
  out=$(run --sha "$SHA" --ext png)
  check "a real image copies" "true" "$(jq -r .ok <<<"$out")"
  sleep 0.5
  check "and the clipboard holds exactly those bytes" "$SHA" \
    "$(wl-paste --type image/png 2>/dev/null | sha256sum | cut -d' ' -f1)"
fi

if (( failed )); then
  printf 'FAIL %d/%d copy-image\n' "$failed" "$checks" >&2
  exit 1
fi
printf 'ok  %d checks copy-image\n' "$checks"
