# STAT-COMMON-030 — STORE Statement

## Source

S154 / Chapter 20 / `STORE Statement` (PDF pp. 543–545).

## Scope

Implement shared semantics, defaults, and applicability checks for STORE Statement; procedure-specific options and result integration belong to the corresponding PROC tickets.

## Acceptance criteria

Write the model, restore it in a new session, and verify parameters, covariance, effects, and class levels; check diagnostics for version mismatches, incompatible stores, and corrupt files.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [store_restore.sas](store_restore.sas) | captured | 0 | [listing](store_restore.expected.txt) / [log](store_restore.oracle.log) | Stored model metadata, restoration and scoring |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
