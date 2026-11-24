# STAT-COMMON-031 — TEST Statement

## Source

S154 / Chapter 20 / `TEST Statement` (PDF pp. 545–547).

## Scope

Implement shared semantics, defaults, and applicability checks for TEST Statement; procedure-specific options and result integration belong to the corresponding PROC tickets.

## Acceptance criteria

Create positive and negative cases for the syntax forms, defaults, and option combinations listed in this section; verify result names, dimensions, and numerical values. Cover nonestimable functions, complex coefficients, adjusted comparisons, and procedure applicability; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [joint_linear_test.sas](joint_linear_test.sas) | captured | 0 | [listing](joint_linear_test.expected.txt) / [log](joint_linear_test.oracle.log) | Joint linear hypothesis, degrees of freedom, F statistic and probability |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
