# STAT-GENMOD-021 — GENMOD — FWDLINK / INVLINK / Programming Statements

S154 / Chapter 51 / `FWDLINK Statement` (PDF p. 3541); S154 / Chapter 51 / `INVLINK Statement` (PDF pp. 3541–3542); S154 / Chapter 51 / `Programming Statements` (PDF pp. 3558–3560).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Verified default procedure context |
| [targeted_statements.sas](targeted_statements.sas) | [output](targeted_statements.expected.txt) | [log](targeted_statements.oracle.log) | 0 | Explicit FWDLINK, INVLINK statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: FWDLINK, INVLINK.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode.
