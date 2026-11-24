# STAT-COMMON-026 — LSMEANS Statement

## Source

S154 / Chapter 20 / `LSMEANS Statement` (PDF pp. 489–510).

## Scope

Implement shared semantics, defaults, and applicability checks for LSMEANS Statement; procedure-specific options and result integration belong to the corresponding PROC tickets.

## Acceptance criteria

Create positive and negative cases for the syntax forms, defaults, and option combinations listed in this section; verify result names, dimensions, and numerical values. Cover nonestimable functions, complex coefficients, adjusted comparisons, and procedure applicability; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [adjusted_lsmeans.sas](adjusted_lsmeans.sas) | captured | 0 | [listing](adjusted_lsmeans.expected.txt) / [log](adjusted_lsmeans.oracle.log) | Adjusted least-squares means, difference and confidence limits |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
