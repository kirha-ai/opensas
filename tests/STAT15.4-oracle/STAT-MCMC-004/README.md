# STAT-MCMC-004 — MCMC — ARRAY / BEGINCNST/ENDCNST / BEGINNODATA/ENDNODATA Statements

S154 / Chapter 80 / `ARRAY Statement` (PDF p. 6117); S154 / Chapter 80 / `BEGINCNST/ENDCNST Statement` (PDF pp. 6117–6119); S154 / Chapter 80 / `BEGINNODATA/ENDNODATA Statements` (PDF p. 6119).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 80.4: Logistic Regression Model with Jeffreys' Prior; explicit statements: ARRAY |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: ARRAY. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.
