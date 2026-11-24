# STAT-LIFETEST-007 — LIFETEST — TEST / Pointwise Confidence Limits in the OUTSURV= Data Set / Simultaneous Confidence Intervals for Kaplan-Meier Curves

## Source

S154 / Chapter 77 / `TEST Statement` (PDF pp. 5668–5669); S154 / Chapter 77 / `Pointwise Confidence Limits in the OUTSURV= Data Set` (PDF pp. 5676–5677); S154 / Chapter 77 / `Simultaneous Confidence Intervals for Kaplan-Meier Curves` (PDF pp. 5677–5679).

## Scope

Implement TEST; Pointwise Confidence Limits in the OUTSURV= Data Set; Simultaneous Confidence Intervals for Kaplan-Meier Curves. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For TEST / Pointwise Confidence Limits in the OUTSURV= Data Set / Simultaneous Confidence Intervals for Kaplan-Meier Curves, use a manually calculable event table to verify risk sets, survival estimates, variances, and intervals; include coincident events/censoring and entirely censored samples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: LIFETEST Procedure; explicit statements: TEST |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: TEST. Remaining statement variants: . Restored the official treatment format from physical PDF page 5642.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
