# STAT-FREQ-011 — FREQ — Odds Ratio and Relative Risks

## Source

S154 / Chapter 47 / `Odds Ratio and Relative Risks` (PDF pp. 3203–3213).

## Scope

Implement Odds Ratio and Relative Risks. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Odds Ratio and Relative Risks, verify event/reference levels, ratio direction, zero cells, and all requested tests/intervals; row or column swaps must produce the correct transformations; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: FREQ Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
