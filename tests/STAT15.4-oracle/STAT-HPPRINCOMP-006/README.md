# STAT-HPPRINCOMP-006 — HPPRINCOMP — OUTPUT / Output Data Sets

S154 / Chapter 65 / `OUTPUT Statement` (PDF pp. 4956–4957); S154 / Chapter 65 / `Output Data Sets` (PDF pp. 4960–4962).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Getting Started: HPPRINCOMP Procedure |
| [statement_output.sas](statement_output.sas) | [output](statement_output.expected.txt) | [log](statement_output.oracle.log) | 1 | Create and print the procedure output data set using default statistic names. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: OUTPUT. Converted state labels to underscore-separated list input, preserving the official missing Murder value for Wyoming.

**statement_output:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions. Converted state labels to underscore-separated list input, preserving the official missing Murder value for Wyoming.
