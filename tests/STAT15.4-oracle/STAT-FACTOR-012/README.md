# STAT-FACTOR-012 — FACTOR — Heywood Cases and Other Anomalies about Communality Estimates / Cautions

S154 / Chapter 44 / `Heywood Cases and Other Anomalies about Communality Estimates` (PDF pp. 2833–2834); S154 / Chapter 44 / `Cautions` (PDF p. 2835).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Maximum-likelihood one- and two-factor fits with HEYWOOD |
| [improper_three_factor.sas](improper_three_factor.sas) | [output](improper_three_factor.expected.txt) | [log](improper_three_factor.oracle.log) | 2 | Deliberately excessive factor retention: warning and improper-optimum error |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. The documented improper three-factor fit is isolated as an explicit negative case.

**improper_three_factor:** Intentional negative case for the documented Heywood/overfactoring cautions. The positive one- and two-factor fits are separate.
