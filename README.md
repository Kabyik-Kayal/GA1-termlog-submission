# termlog exam submission (q-termlog-rec-server)

Submission artifact for the "Decode it in the terminal (termlog)" assignment.

## What to submit

**`submission.tar.gz`** — the file the exam server should fetch.

```
https://raw.githubusercontent.com/Kabyik-Kayal/GA1-termlog-submission/main/submission.tar.gz
```

Verify the download (must match):

```
sha256  6ee421b393db4293146230ddfc4402853717bd0d291e5018ddaad2117d6bc1d2
size    8733 bytes
```

It contains exactly two files:

| File | Purpose |
|---|---|
| `demo.cast` | asciicast v2 terminal recording of the decode |
| `demo.cast.jwt` | signed receipt binding the recording to the Google identity that made it |

Replay it with `termlog play demo.cast` or `asciinema play demo.cast`.

## Verification result

```
termlog verify demo.cast --expect-email 24f2007470@ds.study.iitm.ac.in

ok: true
email check:          valid
receipt signature:    valid
cast hash:            valid
proof header:         valid
Google identity:      valid (online)
Google identity check: online
exit event present:   true
timestamp anchors:    1
```

`Google identity check: online` means the identity was verified against live
Google JWKS, not a cached copy.

## What the recording shows

The challenge ciphertext was fetched **inside** the recorded session and decoded
in the same session with three reversible shell transforms:

```
cipher: 6414n50515648324q2p445
tr  ->  6414a50515648324d2c445     undo ROT13
rev ->  544c2d42384651505a4146     undo reversal
xxd ->  TL-B8FQPZAF                undo hex encoding
```

Decoded value: **`TL-B8FQPZAF`**

### Why the order is detected rather than hardcoded

The transform order rotates along with the ciphertext every 3 hours, so
`solve.sh` brute-forces all 6 orderings and keeps the one producing clean
printable ASCII. (Hex-decoding and reversal commute, so 2 of the 6 tie — that is
expected.)

`solve.sh` also guards `/usr/bin/rev`, which deadlocks on binary input on
Ubuntu. Wrong orderings produce binary bytes, so `rev` is only run when its
input is printable text. Without that guard the script hangs on the first bad
ordering.

## Files in this repo

| File | |
|---|---|
| `submission.tar.gz` | the submission |
| `demo.cast` | the recording (same bytes as inside the tarball) |
| `demo.cast.jwt` | the signed receipt |
| `solve.sh` | fetch + decode, order-agnostic |
| `plain.txt` | decoded value |

## Reproducing

```sh
bash solve.sh        # re-fetches and decodes; writes plain.txt
```

Note the live ciphertext rotates every 3 hours, so a fresh run decodes a
different token than the one recorded above.