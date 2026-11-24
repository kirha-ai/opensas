# STAT-COMMON-033 — Convergence Status

## Source

S154 / Chapter 20 / `Convergence Status` (PDF pp. 549–551).

## Scope

Implement shared semantics, defaults, and applicability checks for convergence Status; procedure-specific options and result integration belong to the corresponding PROC tickets.

## Acceptance criteria

Cover success, iteration limits, infeasibility, and numerical failure; verify status codes, reasons, and result availability, without reporting failed fits as converged.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [iteration_limit.sas](iteration_limit.sas) | captured | 1 | [listing](iteration_limit.expected.txt) / [log](iteration_limit.oracle.log) | Iteration-limit diagnostic and convergence status rather than false success |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
