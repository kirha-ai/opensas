# STAT-GLIMMIX-019 — GLIMMIX — The Odds Ratio Estimates Table / Odds or Odds Ratio / Odds Ratios in Multinomial Models

## Source

S154 / Chapter 52 / `The Odds Ratio Estimates Table` (PDF pp. 3871–3873); S154 / Chapter 52 / `Odds or Odds Ratio` (PDF pp. 3873–3874); S154 / Chapter 52 / `Odds Ratios in Multinomial Models` (PDF pp. 3874–3875).

## Scope

Implement The Odds Ratio Estimates Table; Odds or Odds Ratio; Odds Ratios in Multinomial Models. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For The Odds Ratio Estimates Table / Odds or Odds Ratio / Odds Ratios in Multinomial Models, verify event/reference levels, ratio direction, zero cells, and all requested tests/intervals; row or column swaps must produce the correct transformations; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 52.11: Maximum Likelihood in Proportional Odds Model with Random Effects |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
