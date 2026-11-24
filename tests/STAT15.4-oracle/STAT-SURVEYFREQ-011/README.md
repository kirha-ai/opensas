# STAT-SURVEYFREQ-011 — SURVEYFREQ — Totals / Covariances of Frequency Estimates / Confidence Limits for Totals

## Source

S154 / Chapter 118 / `Totals` (PDF pp. 9642–9643); S154 / Chapter 118 / `Covariances of Frequency Estimates` (PDF pp. 9643–9644); S154 / Chapter 118 / `Confidence Limits for Totals` (PDF pp. 9646–9647).

## Scope

Implement Totals; Covariances of Frequency Estimates; Confidence Limits for Totals. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Totals / Covariances of Frequency Estimates / Confidence Limits for Totals, verify matrix dimensions, symmetry, parameter ordering, and boundaries; compare estimates or transformations for small analytically tractable matrices; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
