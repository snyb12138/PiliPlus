# Danmaku spam detector

This module contains the opt-in v1.2 test implementation for repeated short
danmaku and symbol spam. It is deliberately independent from the permanent
keyword, regular-expression, and sender block lists.

Processing order:

1. Existing explicit user and assistant rules.
2. `DanmakuSpamDetector` on the unmerged raw stream.
3. PiliPlus exact-text merge.
4. Rendering and Purify preview records.

The detector folds full-width ASCII, removes zero-width bypass characters,
normalizes whitespace, removes whitespace between CJK characters, and then
builds both a 64-code-point normalized key and its shortest repeated unit using
the KMP prefix function. Full normalized length is measured after every
normalization step. Window matching is limited to messages with a full length
of 1–12 code points.

All counters include the current danmaku. Sender hashes are salted and valid
only for the current process. They must not be persisted, exported, or used for
cross-session statistics.

The thresholds and test vectors are original to this project. Public filter
projects informed the product and engineering approach only; no third-party
rule text is copied into this module.
