# STAT-SURVEYFREQ-013 — SURVEYFREQ — Sensitivity and Specificity / Risks and Risk Difference / Odds Ratio and Relative Risks

## Source

S154 / Chapter 118 / `Sensitivity and Specificity` (PDF pp. 9652–9653); S154 / Chapter 118 / `Risks and Risk Difference` (PDF pp. 9653–9655); S154 / Chapter 118 / `Odds Ratio and Relative Risks` (PDF pp. 9655–9657).

## Scope

Implement Sensitivity and Specificity; Risks and Risk Difference; Odds Ratio and Relative Risks. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Sensitivity and Specificity / Risks and Risk Difference / Odds Ratio and Relative Risks, verify risk direction, stratified or unstratified estimates, standard errors, and every requested interval; include zero cells and unbalanced margins; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
