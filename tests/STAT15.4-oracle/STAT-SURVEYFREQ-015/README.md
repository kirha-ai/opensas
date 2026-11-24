# STAT-SURVEYFREQ-015 — SURVEYFREQ — Rao-Scott Chi-Square Test / Rao-Scott Likelihood Ratio Chi-Square Test

## Source

S154 / Chapter 118 / `Rao-Scott Chi-Square Test` (PDF pp. 9661–9667); S154 / Chapter 118 / `Rao-Scott Likelihood Ratio Chi-Square Test` (PDF pp. 9667–9668).

## Scope

Implement Rao-Scott Chi-Square Test; Rao-Scott Likelihood Ratio Chi-Square Test. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Rao-Scott Chi-Square Test / Rao-Scott Likelihood Ratio Chi-Square Test, use independently calculated count tables to verify expected frequencies, statistics, corrections, degrees of freedom, and probabilities; include zero rows/columns and small expected counts; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
