# STAT-COMMON-032 — Programming Statements

## Source

S154 / Chapter 20 / `Programming Statements` (PDF pp. 547–549).

## Scope

Implement shared semantics, defaults, and applicability checks for programming Statements; procedure-specific options and result integration belong to the corresponding PROC tickets.

## Acceptance criteria

Execute the documented programming statements in procedure context and verify variable scope, evaluation order, and model-parameter access; do not assume DATA step semantics apply unchanged.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [programmed_nonlinear_model.sas](programmed_nonlinear_model.sas) | captured | 0 | [listing](programmed_nonlinear_model.expected.txt) / [log](programmed_nonlinear_model.oracle.log) | Procedure-scoped parameter expressions and analytic derivatives |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
