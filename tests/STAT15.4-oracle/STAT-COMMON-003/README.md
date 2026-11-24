# STAT-COMMON-003 — Rank-deficient linear algebra and generalized inverses

## Source

S154 / Chapter 4 / `Important Linear Algebra Concepts` (PDF pp. 58–65).

## Scope

Provide interfaces for linear equations, rank determination, projections, and generalized inverses; expose singular and nearly singular states under a consistent precision policy.

## Acceptance criteria

For full-rank, exactly rank-deficient, and nearly collinear matrices, verify decomposition reconstruction, projection identities, and generalized-inverse identities against independent analytic results; explain scale-dependent tolerances and do not return success for numerical failure.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [rank_deficient_regression.sas](rank_deficient_regression.sas) | captured | 0 | [listing](rank_deficient_regression.expected.txt) / [log](rank_deficient_regression.oracle.log) | Exact linear dependence, generalized inverse solution and singularity diagnostics |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
