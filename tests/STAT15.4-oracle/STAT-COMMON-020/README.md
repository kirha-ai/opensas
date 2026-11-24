# STAT-COMMON-020 — CODE Statement

## Source

S154 / Chapter 20 / `CODE Statement` (PDF pp. 421–424).

## Scope

Implement shared semantics, defaults, and applicability checks for CODE Statement; procedure-specific options and result integration belong to the corresponding PROC tickets.

## Acceptance criteria

Execute generated scoring code in an independent DATA step and compare it row by row with in-model predictions; cover class levels, missing values, and transformations; diagnose invalid target languages or options as documented.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [scoring_code.sas](scoring_code.sas) | captured | 0 | [listing](scoring_code.expected.txt) / [log](scoring_code.oracle.log) | Generated DATA step scoring code and fitted model coefficients |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
