# STAT-REG-009 — REG — Multivariate Tests / MTEST

S154 / Chapter 105 / `Multivariate Tests` (PDF pp. 8644–8647); S154 / Chapter 105 / `MTEST Statement` (PDF pp. 8588–8590).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Getting Started: REG Procedure |
| [targeted_statements.sas](targeted_statements.sas) | [output](targeted_statements.expected.txt) | [log](targeted_statements.oracle.log) | 0 | Explicit MTEST statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: MTEST.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode.
