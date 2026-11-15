# Danmaku spam detector

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
