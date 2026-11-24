# STAT-QUANTREG-007 — QUANTREG — ESTIMATE / TEST / Confidence Interval

S154 / Chapter 103 / `ESTIMATE Statement` (PDF pp. 8384–8385); S154 / Chapter 103 / `TEST Statement` (PDF pp. 8392–8393); S154 / Chapter 103 / `Confidence Interval` (PDF pp. 8402–8405).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [targeted_statements.sas](targeted_statements.sas) | [output](targeted_statements.expected.txt) | [log](targeted_statements.oracle.log) | 0 | Explicit ESTIMATE, TEST statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: ESTIMATE, TEST. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax. Native QUANTREG TEST takes model effects; the explicit coefficient combination is requested by ESTIMATE.
