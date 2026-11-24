# STAT-GLMPOWER-005 — GLMPOWER — Keyword-Lists / Sample Size Adjustment Options / Contrasts in Fixed-Effect Univariate Models

## Source

S154 / Chapter 55 / `Keyword-Lists` (PDF pp. 4281–4282); S154 / Chapter 55 / `Sample Size Adjustment Options` (PDF p. 4282); S154 / Chapter 55 / `Contrasts in Fixed-Effect Univariate Models` (PDF pp. 4285–4287).

## Scope

Implement Keyword-Lists; Sample Size Adjustment Options; Contrasts in Fixed-Effect Univariate Models. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Keyword-Lists / Sample Size Adjustment Options / Contrasts in Fixed-Effect Univariate Models, verify forward power calculations, inverse solutions, rounding, and feasible boundaries; substituting the returned value into the original problem must meet the documented accuracy; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: GLMPOWER Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
