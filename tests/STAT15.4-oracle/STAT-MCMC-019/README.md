# STAT-MCMC-019 — MCMC — Regenerating Diagnostics Plots / Caterpillar Plot / ODS Graphics

S154 / Chapter 80 / `Regenerating Diagnostics Plots` (PDF pp. 6208–6210); S154 / Chapter 80 / `Caterpillar Plot` (PDF pp. 6210–6212); S154 / Chapter 80 / `ODS Graphics` (PDF pp. 6244–6245).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Native chain diagnostics and an independently regenerated posterior trace from OUTPOST. |

**documented_feature:** The printed Gelman-Rubin macro is incomplete without external macro source. This self-contained draft captures native MCMC diagnostics and regenerates a trace from saved draws; full caterpillar and Gelman-Rubin variants remain to be added.
