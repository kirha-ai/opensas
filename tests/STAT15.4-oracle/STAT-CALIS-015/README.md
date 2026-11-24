# STAT-CALIS-015 — CALIS — DETERM / PARTIAL / REFMODEL

## Source

S154 / Chapter 33 / `DETERM Statement` (PDF pp. 1549–1550); S154 / Chapter 33 / `PARTIAL Statement` (PDF p. 1616); S154 / Chapter 33 / `REFMODEL Statement` (PDF pp. 1649–1651).

## Scope

Implement DETERM; PARTIAL; REFMODEL. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For DETERM / PARTIAL / REFMODEL, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 33.22: Testing Equality of Covariance and Mean Matrices between Independent Groups; explicit statements: REFMODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: REFMODEL. Remaining statement variants: DETERM, PARTIAL.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
