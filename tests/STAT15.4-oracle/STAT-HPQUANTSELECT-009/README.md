# STAT-HPQUANTSELECT-009 — HPQUANTSELECT — Diagnostic Statistics

## Source

S154 / Chapter 66 / `Diagnostic Statistics` (PDF p. 5002).

## Scope

Implement Diagnostic Statistics. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Diagnostic Statistics, use a manually calculable model to verify diagnostics, leave-one-out changes, and applicable thresholds; include high leverage, near collinearity, and degenerate cases; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Seeded synthetic quantile-regression fixture: Diagnostic Statistics |

**documented_feature:** Bounded adaptation of the documented syntax using 120 explicit seeded synthetic rows and three numeric covariates. It replaces the slow four-fit baseball illustration and preserves this ticket’s targeted behavior.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
