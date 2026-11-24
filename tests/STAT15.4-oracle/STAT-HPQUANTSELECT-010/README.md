# STAT-HPQUANTSELECT-010 — HPQUANTSELECT — CODE

S154 / Chapter 66 / `CODE Statement` (PDF p. 4988).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Seeded synthetic quantile-regression fixture: CODE |
| [statement_code.sas](statement_code.sas) | [output](statement_code.expected.txt) | [log](statement_code.oracle.log) | 0 | Generate DATA step scoring code, execute it against the input rows, and print the scored data. |

**documented_feature:** Bounded adaptation of the documented syntax using 120 explicit seeded synthetic rows and three numeric covariates. It replaces the slow four-fit baseball illustration and preserves this ticket’s targeted behavior.

**statement_code:** Bounded synthetic case; explicitly executes the targeted statement.
