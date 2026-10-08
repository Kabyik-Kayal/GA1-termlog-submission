#!/usr/bin/env bash
# decode.sh - decode an ALREADY-FETCHED challenge response.
#
# Deliberately does NOT fetch anything. The curl must be typed by hand in the
# recorded session so the keyboard capture shows the student pulling the
# ciphertext themselves. This script only does the decoding half:
#
#   tr   - undo ROT13
#   rev  - undo the string reversal
#   xxd  - undo hex encoding
#
# The transform ORDER is not fixed; it rotates with the ciphertext every
# 3 hours. So we brute-force all 6 orderings and keep whichever yields clean
# printable ASCII. (hex-decode and reversal commute, so 2 of the 6 tie.)

set -uo pipefail

SRC="${1:-r.txt}"

if [ ! -s "$SRC" ]; then
  echo "!! $SRC missing or empty."
  echo "   Fetch it first, e.g.:"
  echo "     curl -s \"<challenge-url>\" | tee $SRC"
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# strip the leading '#' comment lines, keep the ciphertext line
grep -v '^#' "$SRC" | grep -v '^[[:space:]]*$' > "$WORK/cipher.txt"
CIPHER="$(cat "$WORK/cipher.txt")"

echo "source   : $SRC"
echo "cipher   : $CIPHER"
echo "length   : $(printf '%s' "$CIPHER" | wc -c) chars"
echo

nonprint() { LC_ALL=C tr -d '[:print:]\n' < "$1" | wc -c; }

# Apply one transform. Returns 1 if that step cannot possibly work.
apply() {
  local tool="$1" in="$2"
  case "$tool" in
    tr)  tr 'A-Za-z' 'N-ZA-Mn-za-m' < "$in" > "$WORK/stage" 2>/dev/null ;;
    xxd) xxd -r -p                   < "$in" > "$WORK/stage" 2>/dev/null ;;
    rev)
      # rev deadlocks on binary input (verified on Ubuntu 24.04), and wrong
      # orderings produce binary bytes, so refuse non-text input up front.
      [ "$(nonprint "$in")" -eq 0 ] || return 1
      rev                             < "$in" > "$WORK/stage" 2>/dev/null ;;
    *)   return 1 ;;
  esac
  return 0
}

echo "== trying all 6 transform orderings =="
echo
FOUND=0
BESTSCORE=-1

for order in "tr xxd rev" "tr rev xxd" "xxd tr rev" "xxd rev tr" "rev tr xxd" "rev xxd tr"; do
  read -r s1 s2 s3 <<<"$order"

  ok=1
  apply "$s1" "$WORK/cipher.txt" && cp "$WORK/stage" "$WORK/cur" || ok=0
  if [ "$ok" -eq 1 ] && { apply "$s2" "$WORK/cur"; }; then
    cp "$WORK/stage" "$WORK/next"
  else
    ok=0
  fi
  [ "$ok" -eq 1 ] && cp "$WORK/next" "$WORK/cur"
  if [ "$ok" -eq 1 ] && { apply "$s3" "$WORK/cur"; }; then
    cp "$WORK/stage" "$WORK/out"
  else
    ok=0
  fi

  if [ "$ok" -eq 0 ]; then
    printf '   %-12s ----  binary junk\n' "$order"
    continue
  fi

  size=$(wc -c < "$WORK/out")
  bad=$(nonprint "$WORK/out")
  if [ "$size" -eq 0 ] || [ "$bad" -ne 0 ]; then
    printf '   %-12s ----  binary junk (%s of %s bytes non-printable)\n' \
           "$order" "$bad" "$size"
    continue
  fi

  # A wrong ordering can land on printable bytes by luck, so score token-ness:
  #   2 = token-like (TL-B8FQPZAF)   1 = alnum run   0 = other printable
  cand="$(cat "$WORK/out")"
  if   printf '%s' "$cand" | grep -qE '^[A-Za-z0-9]+([-_][A-Za-z0-9]+)+$'; then score=2
  elif printf '%s' "$cand" | grep -qE '^[A-Za-z0-9]+$';                        then score=1
  else score=0
  fi

  if [ "$score" -gt "$BESTSCORE" ]; then
    tag="MATCH"
  elif [ "$score" -eq "$BESTSCORE" ]; then
    tag="tie  "
  else
    tag="weak "
  fi
  printf '   %-12s %s score=%s [%s]\n' "$order" "$tag" "$score" "$cand"

  if [ "$score" -gt "$BESTSCORE" ]; then
    BESTSCORE=$score
    cp "$WORK/out" ./plain.txt
    FOUND=1
  fi
done

echo
if [ "$FOUND" -eq 1 ]; then
  echo "== DECODED =="
  cat plain.txt
  echo
  echo "saved to plain.txt"
  [ "$BESTSCORE" -lt 2 ] && echo "note: best match was weakly token-like; re-fetch and re-run if the order just rotated"
else
  echo "!! no ordering produced clean ASCII"
  exit 1
fi