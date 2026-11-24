# STAT-COMMON-027 — LSMESTIMATE Statement

## Source

S154 / Chapter 20 / `LSMESTIMATE Statement` (PDF pp. 510–522).

## Scope

Implement shared semantics, defaults, and applicability checks for LSMESTIMATE Statement; procedure-specific options and result integration belong to the corresponding PROC tickets.

## Acceptance criteria

Create positive and negative cases for the syntax forms, defaults, and option combinations listed in this section; verify result names, dimensions, and numerical values. Cover nonestimable functions, complex coefficients, adjusted comparisons, and procedure applicability; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [lsmestimate_contrast.sas](lsmestimate_contrast.sas) | captured | 0 | [listing](lsmestimate_contrast.expected.txt) / [log](lsmestimate_contrast.oracle.log) | LSMESTIMATE coefficient interpretation and confidence limits |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
