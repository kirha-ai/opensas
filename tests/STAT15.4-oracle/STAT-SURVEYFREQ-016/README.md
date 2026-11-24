# STAT-SURVEYFREQ-016 — SURVEYFREQ — Wald Chi-Square Test / Wald Log-Linear Chi-Square Test

## Source

S154 / Chapter 118 / `Wald Chi-Square Test` (PDF pp. 9668–9670); S154 / Chapter 118 / `Wald Log-Linear Chi-Square Test` (PDF pp. 9670–9671).

## Scope

Implement Wald Chi-Square Test; Wald Log-Linear Chi-Square Test. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Wald Chi-Square Test / Wald Log-Linear Chi-Square Test, use independently calculated count tables to verify expected frequencies, statistics, corrections, degrees of freedom, and probabilities; include zero rows/columns and small expected counts; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
