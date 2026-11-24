# STAT-GENMOD-005 — GENMOD — DEVIANCE / Generalized Linear Models Theory / Multinomial Models

S154 / Chapter 51 / `DEVIANCE Statement` (PDF pp. 3532–3533); S154 / Chapter 51 / `Generalized Linear Models Theory` (PDF pp. 3568–3579); S154 / Chapter 51 / `Multinomial Models` (PDF pp. 3587–3588).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 51.4: Ordinal Model for Multinomial Data |
| [targeted_statements.sas](targeted_statements.sas) | [output](targeted_statements.expected.txt) | [log](targeted_statements.oracle.log) | 0 | Explicit DEVIANCE, VARIANCE statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: DEVIANCE.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode.
