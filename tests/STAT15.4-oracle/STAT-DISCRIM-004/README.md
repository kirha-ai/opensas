# STAT-DISCRIM-004 — DISCRIM — PRIORS / Posterior Probability Error-Rate Estimates

S154 / Chapter 42 / `PRIORS Statement` (PDF pp. 2662–2663); S154 / Chapter 42 / `Posterior Probability Error-Rate Estimates` (PDF pp. 2672–2674).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 42.2: Bivariate Density Estimates and Posterior Probabilities |
| [targeted_statements.sas](targeted_statements.sas) | [output](targeted_statements.expected.txt) | [log](targeted_statements.oracle.log) | 0 | Explicit PRIORS statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: PRIORS.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode.
