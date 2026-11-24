# STAT-BOXPLOT-006 — BOXPLOT — Styles of Box Plots / Positioning Insets / Clipping Extreme Values / ODS Graphics

## Source

S154 / Chapter 32 / `Styles of Box Plots` (PDF pp. 1414–1415); S154 / Chapter 32 / `Positioning Insets` (PDF pp. 1418–1423); S154 / Chapter 32 / `Clipping Extreme Values` (PDF pp. 1425–1429); S154 / Chapter 32 / `ODS Graphics` (PDF p. 1429).

## Scope

Implement Styles of Box Plots; Positioning Insets; Clipping Extreme Values; ODS Graphics. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For Styles of Box Plots / Positioning Insets / Clipping Extreme Values / ODS Graphics, verify graph names, triggering conditions, curve/point data, axes, grouping, and legends; check the relevant PLOTS= and ODS GRAPHICS controls and visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 32.3: Creating Various Styles of Box-and-Whiskers Plots |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Text and ODS trace do not replace visual artifact verification. Synthetic reason labels supply the ID variable required by schematic box styles.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
