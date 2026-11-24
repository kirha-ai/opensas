# STAT-COMMON-010 — Type I sums of squares and estimable functions

## Source

S154 / Chapter 16 / `Type I SS and Estimable Functions` (PDF pp. 284–285); S154 / Chapter 6 / `Introduction to Analysis of Variance Procedures` (PDF pp. 123–134).

## Scope

Implement type I hypothesis construction, degrees of freedom, and sums of squares; preserve differences in definition for unbalanced designs and missing cells.

## Acceptance criteria

For balanced, unbalanced, empty-cell, and reordered-effect designs, verify hypothesis matrices, sums of squares, ranks, and F tests against source examples or independent linear-algebra derivations.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [unbalanced_sums_of_squares.sas](unbalanced_sums_of_squares.sas) | captured | 0 | [listing](unbalanced_sums_of_squares.expected.txt) / [log](unbalanced_sums_of_squares.oracle.log) | Unbalanced effect tests and the requested sums-of-squares type |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
