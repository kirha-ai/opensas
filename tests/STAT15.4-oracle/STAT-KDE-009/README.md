# STAT-KDE-009 — KDE — ODS Graphics

## Source

S154 / Chapter 73 / `ODS Graphics` (PDF pp. 5416–5418).

## Scope

Implement ODS Graphics. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For ODS Graphics, verify graph names, triggering conditions, curve/point data, axes, grouping, and legends; check the relevant PLOTS= and ODS GRAPHICS controls and visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 73.5: Univariate KDE Graphics |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Text and ODS trace do not replace visual artifact verification.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
