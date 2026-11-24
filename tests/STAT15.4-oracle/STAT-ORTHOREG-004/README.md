# STAT-ORTHOREG-004 — ORTHOREG — ESTIMATE / TEST

S154 / Chapter 91 / `ESTIMATE Statement` (PDF pp. 7292–7293); S154 / Chapter 91 / `TEST Statement` (PDF p. 7297).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Getting Started: ORTHOREG Procedure |
| [targeted_statements.sas](targeted_statements.sas) | [output](targeted_statements.expected.txt) | [log](targeted_statements.oracle.log) | 0 | Explicit ESTIMATE, TEST statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: ESTIMATE, TEST.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode. ORTHOREG TEST takes model effects, as documented on physical PDF page 7297.
