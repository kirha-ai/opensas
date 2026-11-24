# STAT-HPSPLIT-014 — HPSPLIT — PERFORMANCE

S154 / Chapter 68 / `PERFORMANCE Statement` (PDF p. 5095).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [statement_performance.sas](statement_performance.sas) | [output](statement_performance.expected.txt) | [log](statement_performance.oracle.log) | 0 | Explicit single-thread performance settings with the documented baseline computation. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: PERFORMANCE.

**statement_performance:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
