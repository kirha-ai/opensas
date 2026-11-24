# STAT-SEQDESIGN-009 — SEQDESIGN — Applicable One-Sample Tests and Sample Size Computation / Applicable Two-Sample Tests and Sample Size Computation / Applicable Regression Parameter Tests and Sample Size Computation

## Source

S154 / Chapter 110 / `Applicable One-Sample Tests and Sample Size Computation` (PDF pp. 9005–9007); S154 / Chapter 110 / `Applicable Two-Sample Tests and Sample Size Computation` (PDF pp. 9007–9015); S154 / Chapter 110 / `Applicable Regression Parameter Tests and Sample Size Computation` (PDF pp. 9015–9018).

## Scope

Implement Applicable One-Sample Tests and Sample Size Computation; Applicable Two-Sample Tests and Sample Size Computation; Applicable Regression Parameter Tests and Sample Size Computation. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Applicable One-Sample Tests and Sample Size Computation / Applicable Two-Sample Tests and Sample Size Computation / Applicable Regression Parameter Tests and Sample Size Computation, verify sample size, mean difference, standard error, t statistic, degrees of freedom, one-/two-sided probabilities, and intervals; include zero variance and insufficient samples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 110.14: Computing Sample Size for Survival Data That Have Uniform Accrual |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
