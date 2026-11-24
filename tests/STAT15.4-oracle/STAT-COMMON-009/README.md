# STAT-COMMON-009 — Estimability and nonestimable result representation

## Source

S154 / Chapter 16 / `Estimability` (PDF pp. 278–284).

## Scope

Implement estimability checks for linear functions, reduction notation, and nonestimable output contracts for ESTIMATE, LSMEANS, CONTRAST, and related consumers.

## Acceptance criteria

Use the source examples to distinguish estimable and nonestimable linear functions; verify status, rank, and diagnostics with missing levels and rank-deficient designs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [estimability.sas](estimability.sas) | captured | 0 | [listing](estimability.expected.txt) / [log](estimability.oracle.log) | Estimability with an empty interaction cell |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
