# STAT-COMMON-028 — NLOPTIONS Statement

## Source

S154 / Chapter 20 / `NLOPTIONS Statement` (PDF pp. 522–539).

## Scope

Implement shared semantics, defaults, and applicability checks for NLOPTIONS Statement; procedure-specific options and result integration belong to the corresponding PROC tickets.

## Acceptance criteria

For each required optimizer, verify objective functions, use of gradients/Hessians, boundaries, stopping rules, and failure status; test analytic optima and difficult initial values rather than only final objective values.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [optimizer_options.sas](optimizer_options.sas) | captured | 0 | [listing](optimizer_options.expected.txt) / [log](optimizer_options.oracle.log) | Explicit optimizer technique, iteration limit and convergence state |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
