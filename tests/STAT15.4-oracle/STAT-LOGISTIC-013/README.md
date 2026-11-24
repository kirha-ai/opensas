# STAT-LOGISTIC-013 — LOGISTIC — ODDSRATIO / UNITS / Odds Ratio Estimation

## Source

S154 / Chapter 79 / `ODDSRATIO Statement` (PDF pp. 5889–5891); S154 / Chapter 79 / `UNITS Statement` (PDF pp. 5903–5904); S154 / Chapter 79 / `Odds Ratio Estimation` (PDF pp. 5922–5925).

## Scope

Implement ODDSRATIO; UNITS; Odds Ratio Estimation. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For ODDSRATIO / UNITS / Odds Ratio Estimation, verify event/reference levels, ratio direction, zero cells, and all requested tests/intervals; row or column swaps must produce the correct transformations; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 79.7: ROC Curve, Customized Odds Ratios, Goodness-of-Fit Statistics, R-Square, and Confidence Limits; explicit statements: UNITS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: UNITS. Remaining statement variants: ODDSRATIO.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
