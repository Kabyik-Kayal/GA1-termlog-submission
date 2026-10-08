#!/usr/bin/env bash
# solve.sh - fetch the challenge and decode it, order-agnostic.
#
# Two things this handles that a hardcoded version gets wrong:
#
#  1. The transform ORDER is not fixed. It changes with each 3-hour rotation
#     of the challenge, so instead of assuming an order we try all 6 and keep
#     whichever produces clean printable ASCII. (hex-decode and reversal
#     commute, so 2 of the 6 normally tie - that's expected, not a bug.)
#
#  2. /usr/bin/rev on Ubuntu HANGS on binary input. A wrong ordering produces
#     binary bytes, so we only run rev when its input is printable ASCII.
#     Without this guard the script wedges forever on the first bad ordering.

set -uo pipefail

URL="https://exam.sanand.workers.dev/questionData?email=24f2007470%40ds.study.iitm.ac.in&quizSign=0CfETLFpAksUEXz1mdzbiVn%2BLQZeyIGuoleBxA84C%2BLxsyJTfDavUiJ3QKpKpKjmek57i8IJQduJJnVxUps0XU1JDd8ZysDFFTUnPzO9QW53MvlF1r4v%2Bq2H88l0S%2FzQUSGFZzRwvf3a6ZjaQDLO1xNYQsC%2Bu9Dhjdw0WA4cqNBlk%2BCTAHRg%2Fy9QjcEd%2B%2Fem8Zm8tOuwexEyXqGq1wbHiTwWbWJJ6XO9n9IqqUKKUf3apyk8esqmdYrt1qaW%2BkIiFu5JNfKR9J%2BsL9qW48W199Z3Jt7s%2BAnliV958Rz6LSpeoL0kfXjXggfhFuuGus9JeOuSD0eFTPTiOHVcvDSgBg%3D%3D&questionId=q-termlog-rec-server"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# count bytes that are NOT printable ASCII (newline allowed)
nonprint() { LC_ALL=C tr -d '[:print:]\n' < "$1" | wc -c; }

# apply one transform; returns 1 if that step cannot work
apply() {
  local tool="$1" in="$2"
  case "$tool" in
    tr)  tr 'A-Za-z' 'N-ZA-Mn-za-m' < "$in" > "$WORK/stage" 2>/dev/null ;;
    xxd) xxd -r -p                   < "$in" > "$WORK/stage" 2>/dev/null ;;
    rev)
      # rev deadlocks on non-text input, so refuse binary input up front
      [ "$(nonprint "$in")" -eq 0 ] || return 1
      rev                             < "$in" > "$WORK/stage" 2>/dev/null ;;
    *)   return 1 ;;
  esac
  return 0
}

echo "== 1. fetch challenge =="
curl -s "$URL" -o "$WORK/resp.txt"
grep -v '^#' "$WORK/resp.txt" | grep -v '^[[:space:]]*$' > "$WORK/cipher.txt"
CIPHER="$(cat "$WORK/cipher.txt")"
echo "   cipher: $CIPHER"
echo "   length: $(printf '%s' "$CIPHER" | wc -c) chars"

echo
echo "== 2. try all 6 transform orderings =="
echo "   (order rotates every 3h, so detect it rather than assume it)"
echo

FOUND=0
BEST=""
BESTSCORE=-1
for order in "tr xxd rev" "tr rev xxd" "xxd tr rev" "xxd rev tr" "rev tr xxd" "rev xxd tr"; do
  read -r s1 s2 s3 <<<"$order"

  ok=1
  apply "$s1" "$WORK/cipher.txt" && cp "$WORK/stage" "$WORK/cur" || ok=0
  if [ "$ok" -eq 1 ]; then
    apply "$s2" "$WORK/cur" && cp "$WORK/stage" "$WORK/cur2" || ok=0
    cp "$WORK/cur2" "$WORK/cur" 2>/dev/null || ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    apply "$s3" "$WORK/cur" && cp "$WORK/stage" "$WORK/out" || ok=0
  fi

  if [ "$ok" -eq 0 ]; then
    printf '   %-12s ----  binary junk (rev refuses non-text input)\n' "$order"
    continue
  fi

  size=$(wc -c < "$WORK/out")
  bad=$(nonprint "$WORK/out")
  if [ "$size" -eq 0 ] || [ "$bad" -ne 0 ]; then
    printf '   %-12s ----  binary junk (%s of %s bytes non-printable)\n' \
           "$order" "$bad" "$size"
    continue
  fi

  # Some wrong orderings can land on printable bytes purely by luck (e.g. hex
  # bytes that all happen to be letters). Score token-likeness to break the tie:
  #   2 = looks like a real token, e.g. TL-B8FQPZAF
  #   1 = plain alnum run
  #   0 = other printable junk
  cand="$(cat "$WORK/out")"
  if printf '%s' "$cand" | grep -qE '^[A-Za-z0-9]+([-_][A-Za-z0-9]+)+$'; then
    score=2
  elif printf '%s' "$cand" | grep -qE '^[A-Za-z0-9]+$'; then
    score=1
  else
    score=0
  fi

  printf '   %-12s %s score=%s [%s]\n' "$order" \
         "$([ "$score" -eq "$BESTSCORE" ] && echo 'MATCH ' || echo 'weak  ')" \
         "$score" "$cand"

  if [ "$score" -gt "$BESTSCORE" ]; then
    BESTSCORE=$score
    BEST="$cand"
    cp "$WORK/out" ./plain.txt
    FOUND=1
  fi
done

echo
if [ "$FOUND" -eq 1 ]; then
  echo "== 3. DECODED =="
  cat plain.txt
  echo "   (saved to plain.txt)"
  if [ "$BESTSCORE" -lt 2 ]; then
    echo
    echo "   NOTE: best candidate is only weakly token-like. The winning"
    echo "   ordering may have rotated since this fetch - just re-run."
  fi
else
  echo "!! No ordering produced clean ASCII - just re-run: bash solve.sh"
fi