# STAT-GLMPOWER-004 — GLMPOWER — POWER / Number-Lists / Name-Lists

## Source

S154 / Chapter 55 / `POWER Statement` (PDF pp. 4270–4277); S154 / Chapter 55 / `Number-Lists` (PDF p. 4281); S154 / Chapter 55 / `Name-Lists` (PDF p. 4281).

## Scope

Implement POWER; Number-Lists; Name-Lists. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For POWER / Number-Lists / Name-Lists, verify forward power calculations, inverse solutions, rounding, and feasible boundaries; substituting the returned value into the original problem must meet the documented accuracy; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: GLMPOWER Procedure; explicit statements: POWER |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: POWER. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
