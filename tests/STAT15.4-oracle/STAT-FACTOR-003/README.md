# STAT-FACTOR-003 — FACTOR — PARTIAL / Variable Weights and Variance Explained / Simplicity Functions for Rotations

S154 / Chapter 44 / `PARTIAL Statement` (PDF p. 2817); S154 / Chapter 44 / `Variable Weights and Variance Explained` (PDF pp. 2829–2830); S154 / Chapter 44 / `Simplicity Functions for Rotations` (PDF pp. 2830–2831).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 44.5: Using Confidence Intervals to Locate Salient Factor Loadings |
| [targeted_statements.sas](targeted_statements.sas) | [output](targeted_statements.expected.txt) | [log](targeted_statements.oracle.log) | 0 | Explicit PARTIAL statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: PARTIAL.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode.
