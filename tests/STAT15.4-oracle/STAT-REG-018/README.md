# STAT-REG-018 — REG — Construction of Q-Q and P-P Plots / Plot Options Superseded by ODS Graphics / ODS Graphics

## Source

S154 / Chapter 105 / `Construction of Q-Q and P-P Plots` (PDF p. 8649); S154 / Chapter 105 / `Plot Options Superseded by ODS Graphics` (PDF pp. 8652–8668); S154 / Chapter 105 / `ODS Graphics` (PDF pp. 8670–8676).

## Scope

Implement Construction of Q-Q and P-P Plots; Plot Options Superseded by ODS Graphics; ODS Graphics. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For Construction of Q-Q and P-P Plots / Plot Options Superseded by ODS Graphics / ODS Graphics, verify graph names, triggering conditions, curve/point data, axes, grouping, and legends; check the relevant PLOTS= and ODS GRAPHICS controls and visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: REG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Text and ODS trace do not replace visual artifact verification.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
