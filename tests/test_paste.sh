#!/usr/bin/env bash
# Tests for scripts/paste-image.
#
#     tests/run
#
# The clipboard path cannot be exercised head-less, so the script takes
# --file as well; that is also how a copied image *path* gets imported, so it
# is a real entry point rather than a test seam.
set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$HERE/../scripts/paste-image"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

checks=0
failed=0
check() { # check <name> <expected> <actual>
  checks=$((checks + 1))
  if [[ "$2" != "$3" ]]; then
    failed=$((failed + 1))
    printf 'FAIL %s\n    expected %s\n    got      %s\n' "$1" "$2" "$3" >&2
  fi
}

DATA="$WORK/data"
mkdir -p "$DATA"
magick -size 1200x900 gradient:red-blue "$WORK/wide.png"
magick -size 90x1400 gradient:green-black "$WORK/tall.png"
printf 'not an image at all\n' > "$WORK/notes.txt"

SHA=$(sha256sum "$WORK/wide.png" | cut -d' ' -f1)

# --- a normal paste -------------------------------------------------------
out=$("$SCRIPT" --dir "$DATA" --file "$WORK/wide.png" 2>/dev/null)
check "importing a png reports ok" "true" "$(jq -r .ok <<<"$out")"
check "the reported hash is the file's own sha256" "$SHA" "$(jq -r .sha <<<"$out")"
check "the extension is reported" "png" "$(jq -r .ext <<<"$out")"
check "the source dimensions are reported" "1200 900" "$(jq -r '"\(.w) \(.h)"' <<<"$out")"
check "the blob is stored under its hash" "yes" \
  "$([[ -f "$DATA/blobs/$SHA.png" ]] && echo yes || echo no)"
check "a thumbnail is rendered" "yes" \
  "$([[ -f "$DATA/thumbs/$SHA.webp" ]] && echo yes || echo no)"

# The thumbnail is what every list loads, so its size is a promise, not a
# detail: a full-resolution "thumbnail" would undo the point of having one.
long=$(magick identify -format '%[fx:max(w,h)]' "$DATA/thumbs/$SHA.webp")
check "the thumbnail is bounded to 320px on its long edge" "320" "$long"

# Guarded: a check whose file is missing must still report as one failure
# rather than abort the suite and hide every check after it.
size() { stat -c%s "$1" 2>/dev/null || echo 0; }
smaller=$(( $(size "$DATA/thumbs/$SHA.webp") > 0 &&
            $(size "$DATA/thumbs/$SHA.webp") < $(size "$DATA/blobs/$SHA.png") ))
check "the thumbnail is smaller than the original" "1" "$smaller"

# --- a very tall image ----------------------------------------------------
out=$("$SCRIPT" --dir "$DATA" --file "$WORK/tall.png" 2>/dev/null)
tsha=$(jq -r .sha <<<"$out")
tall_long=$(magick identify -format '%[fx:max(w,h)]' "$DATA/thumbs/$tsha.webp")
check "a tall image is bounded on its long edge too" "320" "$tall_long"

# --- pasting the same image twice -----------------------------------------
before=$(stat -c%Y "$DATA/blobs/$SHA.png" 2>/dev/null || echo 0)
sleep 1.1
out=$("$SCRIPT" --dir "$DATA" --file "$WORK/wide.png" 2>/dev/null)
after=$(stat -c%Y "$DATA/blobs/$SHA.png" 2>/dev/null || echo 0)
check "pasting the same image again reports the same hash" "$SHA" "$(jq -r .sha <<<"$out")"
check "pasting the same image again reports the reuse" "true" "$(jq -r .deduped <<<"$out")"
check "the stored blob is left untouched" "$before" "$after"
check "no second copy is written" "1" "$(find "$DATA/blobs" -name "$SHA.*" | wc -l)"

# --- things that are not images -------------------------------------------
out=$("$SCRIPT" --dir "$DATA" --file "$WORK/notes.txt" 2>/dev/null)
check "a text file is refused" "false" "$(jq -r .ok <<<"$out")"
check "a refusal explains itself" "1" \
  "$([[ -n "$(jq -r '.error // ""' <<<"$out")" ]] && echo 1 || echo 0)"
check "a refused import writes nothing" "2" "$(ls "$DATA/blobs" | wc -l)"

out=$("$SCRIPT" --dir "$DATA" --file "$WORK/does-not-exist.png" 2>/dev/null)
check "a missing file is refused" "false" "$(jq -r .ok <<<"$out")"

# A failure has to stay machine-readable: the QML side parses stdout and has
# no other way to find out what happened.
check "a refusal is still valid JSON" "0" \
  "$(jq -e . >/dev/null 2>&1 <<<"$out"; echo $?)"

if (( failed )); then
  printf 'FAIL %d/%d paste-image\n' "$failed" "$checks" >&2
  exit 1
fi
printf 'ok  %d checks paste-image\n' "$checks"
