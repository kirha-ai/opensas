# STAT-GLIMMIX-022 — GLIMMIX — CODE

S154 / Chapter 52 / `CODE Statement` (PDF p. 3732).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Getting Started: GLIMMIX Procedure |
| [statement_code.sas](statement_code.sas) | [output](statement_code.expected.txt) | [log](statement_code.oracle.log) | 0 | Generate DATA step scoring code, execute it against the input rows, and print the scored data. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: CODE.

**statement_code:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
