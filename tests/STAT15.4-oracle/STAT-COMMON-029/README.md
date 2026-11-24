# STAT-COMMON-029 — SLICE Statement

## Source

S154 / Chapter 20 / `SLICE Statement` (PDF pp. 539–543).

## Scope

Implement shared semantics, defaults, and applicability checks for SLICE Statement; procedure-specific options and result integration belong to the corresponding PROC tickets.

## Acceptance criteria

Create positive and negative cases for the syntax forms, defaults, and option combinations listed in this section; verify result names, dimensions, and numerical values. Cover nonestimable functions, complex coefficients, adjusted comparisons, and procedure applicability; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [slice_simple_effects.sas](slice_simple_effects.sas) | captured | 0 | [listing](slice_simple_effects.expected.txt) / [log](slice_simple_effects.oracle.log) | Simple effects and pairwise differences within interaction slices |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
