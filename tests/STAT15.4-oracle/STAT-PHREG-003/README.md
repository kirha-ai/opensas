# STAT-PHREG-003 — PHREG — Time and CLASS Variables Usage / Counting Process Style of Input / Left-Truncation of Failure Times / Caution about Using Survival Data with Left Truncation

S154 / Chapter 92 / `Time and CLASS Variables Usage` (PDF pp. 7392–7396); S154 / Chapter 92 / `Counting Process Style of Input` (PDF pp. 7397–7398); S154 / Chapter 92 / `Left-Truncation of Failure Times` (PDF pp. 7398–7399); S154 / Chapter 92 / `Caution about Using Survival Data with Left Truncation` (PDF pp. 7446–7449).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 92.6: Model Using Time-Dependent Explanatory Variables |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Converted 103 official fixed-column heart-transplant records to explicit list input. Missing transplant dates and tissue-typing values remain explicit missing fields, rather than collapsed column gaps.
