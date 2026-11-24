# STAT-TPSPLINE-008 — TPSPLINE — ODS Graphics

## Source

S154 / Chapter 125 / `ODS Graphics` (PDF pp. 10312–10313).

## Scope

Implement ODS Graphics. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For ODS Graphics, verify graph names, triggering conditions, curve/point data, axes, grouping, and legends; check the relevant PLOTS= and ODS GRAPHICS controls and visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: TPSPLINE Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Text and ODS trace do not replace visual artifact verification. Routes traditional SAS/GRAPH output to a temporary SVG file in the session, allowing independent replay without server-directory write permissions.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
