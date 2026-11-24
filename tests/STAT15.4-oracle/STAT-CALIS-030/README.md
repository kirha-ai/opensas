# STAT-CALIS-030 — CALIS — PATHDIAGRAM / Path Diagrams: Layout Algorithms, Default Settings, and Customization

## Source

S154 / Chapter 33 / `PATHDIAGRAM Statement` (PDF pp. 1626–1638); S154 / Chapter 33 / `Path Diagrams: Layout Algorithms, Default Settings, and Customization` (PDF pp. 1735–1757).

## Scope

Implement PATHDIAGRAM; Path Diagrams: Layout Algorithms, Default Settings, and Customization. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For PATHDIAGRAM / Path Diagrams: Layout Algorithms, Default Settings, and Customization, verify graph names, triggering conditions, curve/point data, axes, grouping, and legends; check the relevant PLOTS= and ODS GRAPHICS controls and visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 33.17: Path Analysis: Stability of Alienation; explicit statements: PATHDIAGRAM |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PATHDIAGRAM. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
