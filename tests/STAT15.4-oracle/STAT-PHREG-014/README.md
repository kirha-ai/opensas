# STAT-PHREG-014 — PHREG — Hazard Ratios / HAZARDRATIO / Confidence Limits for a Hazard Ratio

S154 / Chapter 92 / `Hazard Ratios` (PDF pp. 7409–7412); S154 / Chapter 92 / `HAZARDRATIO Statement` (PDF pp. 7364–7367); S154 / Chapter 92 / `Confidence Limits for a Hazard Ratio` (PDF pp. 7416–7418).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 92.13: Bayesian Analysis of the Cox Model; explicit statements: HAZARDRATIO |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: HAZARDRATIO. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. Restored the official yesno format and the missing terminator of the prior-input DATALINES.
