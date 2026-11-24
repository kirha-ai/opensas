# STAT-LIFEREG-014 — LIFEREG — INSET / Probability Plotting / Plot Options Superseded by ODS Graphics / ODS Graphics

## Source

S154 / Chapter 76 / `INSET Statement` (PDF pp. 5550–5551); S154 / Chapter 76 / `Probability Plotting` (PDF pp. 5576–5581); S154 / Chapter 76 / `Plot Options Superseded by ODS Graphics` (PDF pp. 5590–5599); S154 / Chapter 76 / `ODS Graphics` (PDF pp. 5601–5602).

## Scope

Implement INSET; Probability Plotting; Plot Options Superseded by ODS Graphics; ODS Graphics. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For INSET / Probability Plotting / Plot Options Superseded by ODS Graphics / ODS Graphics, verify graph names, triggering conditions, curve/point data, axes, grouping, and legends; check the relevant PLOTS= and ODS GRAPHICS controls and visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 76.6: Probability Plotting—Arbitrary Censoring; explicit statements: INSET |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: INSET. Remaining statement variants: . Text and ODS trace do not replace visual artifact verification.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
