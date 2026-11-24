# STAT-FREQ-005 — FREQ — Chi-Square Tests and Statistics

## Source

S154 / Chapter 47 / `Chi-Square Tests and Statistics` (PDF pp. 3165–3170).

## Scope

Implement Chi-Square Tests and Statistics. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Chi-Square Tests and Statistics, use independently calculated count tables to verify expected frequencies, statistics, corrections, degrees of freedom, and probabilities; include zero rows/columns and small expected counts; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 47.3: Chi-Square Goodness-of-Fit Tests |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
