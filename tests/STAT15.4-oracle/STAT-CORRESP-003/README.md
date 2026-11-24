# STAT-CORRESP-003 — CORRESP — SUPPLEMENTARY / TABLES / Using the TABLES

## Source

S154 / Chapter 41 / `SUPPLEMENTARY Statement` (PDF p. 2590); S154 / Chapter 41 / `TABLES Statement` (PDF pp. 2590–2591); S154 / Chapter 41 / `Using the TABLES Statement` (PDF pp. 2592–2600).

## Scope

Implement SUPPLEMENTARY; TABLES; Using the TABLES. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For SUPPLEMENTARY / TABLES / Using the TABLES, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 41.2: Simple Correspondence Analysis of U.S. Population; explicit statements: SUPPLEMENTARY |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: SUPPLEMENTARY. Remaining statement variants: TABLES. Preserved region labels with underscores so list input does not depend on PDF column spacing.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
