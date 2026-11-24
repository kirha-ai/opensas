# STAT-REG-011 — REG — REWEIGHT / Reweighting Observations in an Analysis

S154 / Chapter 105 / `REWEIGHT Statement` (PDF pp. 8595–8598); S154 / Chapter 105 / `Reweighting Observations in an Analysis` (PDF pp. 8636–8642).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Getting Started: REG Procedure |
| [targeted_statements.sas](targeted_statements.sas) | [output](targeted_statements.expected.txt) | [log](targeted_statements.oracle.log) | 0 | Explicit REWEIGHT statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: REWEIGHT.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode.
