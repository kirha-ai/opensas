# STAT-BCHOICE-011 — BCHOICE — Regenerating Diagnostics Plots / ODS Graphics

S154 / Chapter 30 / `Regenerating Diagnostics Plots` (PDF p. 1222); S154 / Chapter 30 / `ODS Graphics` (PDF p. 1227).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 30.5: Heterogeneity Affected by Individual Characteristics |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Text and ODS trace do not replace visual artifact verification. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.
