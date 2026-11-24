# STAT-BOXPLOT-005 — BOXPLOT — INSET / INSETGROUP / PLOT / Summary Statistics Represented by Box Plots

## Source

S154 / Chapter 32 / `INSET Statement` (PDF pp. 1378–1381); S154 / Chapter 32 / `INSETGROUP Statement` (PDF pp. 1381–1384); S154 / Chapter 32 / `PLOT Statement` (PDF pp. 1384–1409); S154 / Chapter 32 / `Summary Statistics Represented by Box Plots` (PDF p. 1409).

## Scope

Implement INSET; INSETGROUP; PLOT; Summary Statistics Represented by Box Plots. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For INSET / INSETGROUP / PLOT / Summary Statistics Represented by Box Plots, verify graph names, triggering conditions, curve/point data, axes, grouping, and legends; check the relevant PLOTS= and ODS GRAPHICS controls and visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 32.1: Displaying Summary Statistics in a Box Plot; explicit statements: INSET, INSETGROUP, PLOT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: INSET, INSETGROUP, PLOT. Remaining statement variants: . Text and ODS trace do not replace visual artifact verification.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
