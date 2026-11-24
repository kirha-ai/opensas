# STAT-NLIN-011 — NLIN — Measures of Nonlinearity, Diagnostics and Inference

## Source

S154 / Chapter 88 / `Measures of Nonlinearity, Diagnostics and Inference` (PDF pp. 7016–7024).

## Scope

Implement Measures of Nonlinearity, Diagnostics and Inference. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Measures of Nonlinearity, Diagnostics and Inference, use a manually calculable model to verify diagnostics, leave-one-out changes, and applicable thresholds; include high leverage, near collinearity, and degenerate cases; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 88.6: ODS Graphics and Diagnostics |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
