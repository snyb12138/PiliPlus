# Danmaku spam detector

## 1.3.0 development contract

- Aggressive Latin-text filtering is a separate, default-off switch. Any one
  of isolation, mixed punctuation, or absence from the small built-in network
  combination table may block a message. This deliberately accepts false
  positives; it is not semantic language detection.
- Isolation is computed on the sorted raw batch, before filtering/merging.
  A segment edge with incomplete +/-2 second coverage is unknown, not isolated.
- Manual exact-whole-message allowlists bypass automatic detection only.
  Explicit keyword/regex/sender block rules still take priority. All allowlist
  additions require a deliberate user action; no sample promotes itself.
- Learning samples come only from manual content-blocking actions, retain raw
  text and the selected keyword/mode, deduplicate and cap at 1000 records. The
  samples and exact manual whitelist are explicitly exported together as JSON;
  no upload or rule learning happens inside the app. No sender identifiers,
  cid, URLs or credentials are included. Both samples and allowlists use the
  existing profile backup.
- Character runs may be shortened to three for display. Filtering, preview and
  keyword extraction retain the original text. Embedded primitive short phrases
  use a bounded scan, not a backtracking regex.
- Time templates accept limited Chinese/English duration and relative-time
  forms, with controlled trailing punctuation/check-in suffixes. Normal full
  sentences remain out of scope. Short symbolic fragments also require a
  repetition window; a lone symbol is not automatically blocked.
- Window counts use sorted timeline indexes and binary bounds, not a scan of
  all historical events on every new message. Existing half-open boundaries,
  duplicate-event decisions and three-cid LRU retention are preserved.

This module contains the opt-in v1.2 test implementation for repeated short
danmaku and symbol spam. It is deliberately independent from the permanent
keyword, regular-expression, and sender block lists.

Processing order:

1. Existing explicit user and assistant rules.
2. `TemplateSpamTracker` on whole-message count/relative-time candidates.
3. `DanmakuSpamDetector` on the unmerged raw stream.
4. PiliPlus exact-text merge.
5. Rendering and Purify preview records.

The detector folds full-width ASCII, removes zero-width bypass characters,
normalizes whitespace, removes whitespace between CJK characters, and then
builds both a 64-code-point normalized key and its shortest repeated unit using
the KMP prefix function. Full normalized length is measured after every
normalization step. Window matching is limited to messages with a full length
of 1–12 code points.

All counters include the current danmaku. Sender hashes are salted and valid
only for the current process. They must not be persisted, exported, or used for
cross-session statistics.

`TemplateSpamTracker` only accepts a whole message such as `5000+` or
`5分钟前`; a normal sentence containing the same token is ignored. Count and
time variants share a template key while time units remain distinct. The
global five-second and same-sender ten-second windows are left-closed and
right-open. Decisions are keyed by the source danmaku id so segment reloads
and seeking do not count an event twice. Up to three cid states are retained
using LRU order, and every sender token remains process-local.

The internal detector also catches long character runs embedded in otherwise
different text, such as an ordinary prefix followed by five repeated ASCII
letters. Expressive CJK characters keep the existing six-character threshold.
Long ASCII-only strings of at least 16 code points are classified as probable
keyboard mashing only when they contain at least 12 letters and no more than
20 percent vowels. Short Bilibili identifiers therefore remain outside this
heuristic.

The thresholds and test vectors are original to this project. Public filter
projects informed the product and engineering approach only; no third-party
rule text is copied into this module.
