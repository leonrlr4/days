#!/usr/bin/env bash
# Tests for scripts/gc-blobs, the only thing here that deletes a user's file.
#
#     tests/run
set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$HERE/../scripts/gc-blobs"
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
exists() { [[ -e "$1" ]] && echo yes || echo no; }

seed() { # seed <dir>
  local d=$1
  rm -rf "$d"; mkdir -p "$d/days" "$d/blobs" "$d/thumbs"
  cat > "$d/days/2026-09-11.json" <<'JSON'
{"v":1,"date":"2026-09-11","tasks":[
  {"id":"a","text":"kept","done":false,"created":"2026-09-11","note":"","subs":[],
   "atts":[{"sha":"aa11aa11","ext":"png","w":10,"h":10,"bytes":1}]}]}
JSON
  cat > "$d/days/2026-09-10.json" <<'JSON'
{"v":1,"date":"2026-09-10","tasks":[
  {"id":"b","text":"also kept","done":true,"created":"2026-09-10","note":"","subs":[],
   "atts":[{"sha":"bb22bb22","ext":"jpg","w":10,"h":10,"bytes":1}]}]}
JSON
  for sha in aa11aa11 bb22bb22 cc33cc33 dd44dd44; do
    printf 'x' > "$d/blobs/$sha.png"
    printf 'x' > "$d/thumbs/$sha.webp"
  done
  mv "$d/blobs/bb22bb22.png" "$d/blobs/bb22bb22.jpg"
}

# --- a full sweep ---------------------------------------------------------
D="$WORK/full"; seed "$D"
out=$("$SCRIPT" --dir "$D" 2>/dev/null)
check "a sweep reports ok" "true" "$(jq -r .ok <<<"$out")"
check "an unreferenced blob is removed" "no" "$(exists "$D/blobs/cc33cc33.png")"
check "its thumbnail goes with it" "no" "$(exists "$D/thumbs/cc33cc33.webp")"
check "the second orphan goes too" "no" "$(exists "$D/blobs/dd44dd44.png")"
check "a referenced blob is kept" "yes" "$(exists "$D/blobs/aa11aa11.png")"
check "its thumbnail is kept" "yes" "$(exists "$D/thumbs/aa11aa11.webp")"
check "a blob referenced from another day is kept" "yes" "$(exists "$D/blobs/bb22bb22.jpg")"
check "the removals are reported" "cc33cc33 dd44dd44" \
  "$(jq -r '[.removed[]] | sort | join(" ")' <<<"$out")"

# --- one hash at a time ---------------------------------------------------
D="$WORK/one"; seed "$D"
out=$("$SCRIPT" --dir "$D" --sha cc33cc33 2>/dev/null)
check "the named orphan is removed" "no" "$(exists "$D/blobs/cc33cc33.png")"
check "an orphan that was not named is left alone" "yes" "$(exists "$D/blobs/dd44dd44.png")"

D="$WORK/named-live"; seed "$D"
out=$("$SCRIPT" --dir "$D" --sha aa11aa11 2>/dev/null)
check "naming a referenced hash does not remove it" "yes" "$(exists "$D/blobs/aa11aa11.png")"
check "and it is reported as kept" "aa11aa11" "$(jq -r '.kept | join(" ")' <<<"$out")"

# --- the safety property --------------------------------------------------
# References are re-derived from the day files, so a day file that cannot be
# read means the reference set is unknown -- and deleting against an unknown
# reference set is how a user loses a screenshot they still had attached.
D="$WORK/corrupt"; seed "$D"
printf '{"v":1,"tas' > "$D/days/2026-09-09.json"
out=$("$SCRIPT" --dir "$D" 2>/dev/null)
check "an unreadable day file stops the sweep" "false" "$(jq -r .ok <<<"$out")"
check "and nothing is deleted" "yes" "$(exists "$D/blobs/cc33cc33.png")"
check "the refusal says which file" "1" \
  "$(jq -r '.error' <<<"$out" | grep -c '2026-09-09')"

# --- a store with no days at all ------------------------------------------
D="$WORK/empty"; rm -rf "$D"; mkdir -p "$D/days" "$D/blobs" "$D/thumbs"
printf 'x' > "$D/blobs/ee55ee55.png"
out=$("$SCRIPT" --dir "$D" 2>/dev/null)
check "an empty store still sweeps" "true" "$(jq -r .ok <<<"$out")"
check "a blob nothing references is removed" "no" "$(exists "$D/blobs/ee55ee55.png")"

# --- bad arguments --------------------------------------------------------
out=$("$SCRIPT" 2>/dev/null)
check "a missing --dir is refused" "false" "$(jq -r .ok <<<"$out")"
check "the refusal is valid JSON" "0" "$(jq -e . >/dev/null 2>&1 <<<"$out"; echo $?)"

out=$("$SCRIPT" --dir "$WORK/not-a-store" 2>/dev/null)
check "a directory that is not a store is refused" "false" "$(jq -r .ok <<<"$out")"

# A hash is used to build a path, so anything that is not a hash is refused
# before it gets near the filesystem.
D="$WORK/traversal"; seed "$D"
out=$("$SCRIPT" --dir "$D" --sha "../days/2026-09-11" 2>/dev/null)
check "a hash that is not a hash is refused" "false" "$(jq -r .ok <<<"$out")"
check "and the day file it pointed at survives" "yes" "$(exists "$D/days/2026-09-11.json")"

# --- staging leftovers -------------------------------------------------------
# paste-image stages through mktemp before renaming into place. A kill in
# between leaves a full-size copy of the image behind, and nothing else ever
# looks at it.
D="$WORK/staging"; seed "$D"
printf 'x' > "$D/blobs/staging.OLDFILE1"
printf 'x' > "$D/thumbs/staging.OLDFILE2"
touch -d '3 hours ago' "$D/blobs/staging.OLDFILE1" "$D/thumbs/staging.OLDFILE2"
printf 'x' > "$D/blobs/staging.FRESHONE"
out=$("$SCRIPT" --dir "$D" 2>/dev/null)
check "a stale staging file is swept" "no" "$(exists "$D/blobs/staging.OLDFILE1")"
check "including under thumbs" "no" "$(exists "$D/thumbs/staging.OLDFILE2")"
# A paste in flight right now must not have its staging file pulled out from
# under it.
check "a staging file still in use is left alone" "yes" "$(exists "$D/blobs/staging.FRESHONE")"
check "and referenced blobs are still untouched" "yes" "$(exists "$D/blobs/aa11aa11.png")"

# --- bad arguments -----------------------------------------------------------
timeout 5 "$SCRIPT" --dir >/dev/null 2>&1
check "a flag with no value exits instead of spinning" "1" \
  "$([[ $? -ne 124 ]] && echo 1 || echo 0)"

if (( failed )); then
  printf 'FAIL %d/%d gc-blobs\n' "$failed" "$checks" >&2
  exit 1
fi
printf 'ok  %d checks gc-blobs\n' "$checks"
