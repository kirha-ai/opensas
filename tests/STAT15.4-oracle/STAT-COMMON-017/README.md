# STAT-COMMON-017 — Ranks, ties, and nonparametric test interfaces

## Source

S154 / Chapter 17 / `Introduction to Nonparametric Analysis` (PDF pp. 295–302).

## Scope

Implement shared rank, tie-group, and statistic interfaces for nonparametric procedures; distinguish exact distributions from asymptotic approximations.

## Acceptance criteria

Verify ranks and tie corrections with tied, reverse-ordered, constant, and missing data; enumerate permutations to check small-sample statistics.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [ranks_with_ties.sas](ranks_with_ties.sas) | captured | 0 | [listing](ranks_with_ties.expected.txt) / [log](ranks_with_ties.oracle.log) | Tied ranks and exact versus asymptotic rank inference |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
