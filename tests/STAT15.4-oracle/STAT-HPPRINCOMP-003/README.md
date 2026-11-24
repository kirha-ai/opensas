# STAT-HPPRINCOMP-003 — HPPRINCOMP — PARTIAL / Eigenvalue Decomposition / NIPALS

S154 / Chapter 65 / `PARTIAL Statement` (PDF pp. 4957–4958); S154 / Chapter 65 / `Eigenvalue Decomposition` (PDF p. 4959); S154 / Chapter 65 / `NIPALS` (PDF p. 4959).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Getting Started: HPPRINCOMP Procedure |
| [targeted_statements.sas](targeted_statements.sas) | [output](targeted_statements.expected.txt) | [log](targeted_statements.oracle.log) | 0 | Explicit PARTIAL statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: PARTIAL. Converted state labels to underscore-separated list input, preserving the official missing Murder value for Wyoming.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode.
