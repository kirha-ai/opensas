# STAT-COMMON-025 — ESTIMATE Statement

## Source

S154 / Chapter 20 / `ESTIMATE Statement` (PDF pp. 472–489).

## Scope

Implement shared semantics, defaults, and applicability checks for ESTIMATE Statement; procedure-specific options and result integration belong to the corresponding PROC tickets.

## Acceptance criteria

Create positive and negative cases for the syntax forms, defaults, and option combinations listed in this section; verify result names, dimensions, and numerical values. Cover nonestimable functions, complex coefficients, adjusted comparisons, and procedure applicability; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [estimate_coefficients.sas](estimate_coefficients.sas) | captured | 0 | [listing](estimate_coefficients.expected.txt) / [log](estimate_coefficients.oracle.log) | ESTIMATE coefficient mapping, estimability and standard errors |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
