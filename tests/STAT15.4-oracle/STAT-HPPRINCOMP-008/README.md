# STAT-HPPRINCOMP-008 — HPPRINCOMP — PERFORMANCE

S154 / Chapter 65 / `PERFORMANCE Statement` (PDF p. 4958).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Getting Started: HPPRINCOMP Procedure |
| [statement_performance.sas](statement_performance.sas) | [output](statement_performance.expected.txt) | [log](statement_performance.oracle.log) | 1 | Explicit single-thread performance settings with the documented baseline computation. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: PERFORMANCE. Converted state labels to underscore-separated list input, preserving the official missing Murder value for Wyoming.

**statement_performance:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions. Converted state labels to underscore-separated list input, preserving the official missing Murder value for Wyoming.
