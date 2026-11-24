# STAT-MCMC-019 — MCMC — Regenerating Diagnostics Plots / Caterpillar Plot / ODS Graphics

## Source

S154 / Chapter 80 / `Regenerating Diagnostics Plots` (PDF pp. 6208–6210); S154 / Chapter 80 / `Caterpillar Plot` (PDF pp. 6210–6212); S154 / Chapter 80 / `ODS Graphics` (PDF pp. 6244–6245).

## Scope

Implement Regenerating Diagnostics Plots; Caterpillar Plot; ODS Graphics. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For Regenerating Diagnostics Plots / Caterpillar Plot / ODS Graphics, verify graph names, triggering conditions, curve/point data, axes, grouping, and legends; check the relevant PLOTS= and ODS GRAPHICS controls and visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Native chain diagnostics and an independently regenerated posterior trace from OUTPOST. |

**documented_feature:** The printed Gelman-Rubin macro is incomplete without external macro source. This self-contained draft captures native MCMC diagnostics and regenerates a trace from saved draws; full caterpillar and Gelman-Rubin variants remain to be added.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
