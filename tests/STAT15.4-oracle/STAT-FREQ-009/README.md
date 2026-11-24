# STAT-FREQ-009 — FREQ — Risks and Risk Differences

## Source

S154 / Chapter 47 / `Risks and Risk Differences` (PDF pp. 3188–3199).

## Scope

Implement Risks and Risk Differences. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Risks and Risk Differences, verify risk direction, stratified or unstratified estimates, standard errors, and every requested interval; include zero cells and unbalanced margins; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: FREQ Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
