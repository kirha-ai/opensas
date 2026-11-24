# STAT-TTEST-005 — TTEST — One-Sample Design

## Source

S154 / Chapter 128 / `One-Sample Design` (PDF pp. 10620–10623).

## Scope

Implement One-Sample Design. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For One-Sample Design, verify sample size, mean difference, standard error, t statistic, degrees of freedom, one-/two-sided probabilities, and intervals; include zero variance and insufficient samples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [one_sided_court.sas](one_sided_court.sas) | captured | 0 | [listing](one_sided_court.expected.txt) / [log](one_sided_court.oracle.log) | Upper one-sided p-value and one-sided 90% interval |
| [invalid_alpha.sas](invalid_alpha.sas) | captured | 2 | [listing](invalid_alpha.expected.txt) / [log](invalid_alpha.oracle.log) | Documented invalid ALPHA boundary |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
