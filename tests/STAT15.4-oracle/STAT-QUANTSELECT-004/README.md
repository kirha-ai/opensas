# STAT-QUANTSELECT-004 — QUANTSELECT — Quasi-Likelihood Information Criteria / Quantile Process Regression / Observation Quantile Level

## Source

S154 / Chapter 104 / `Quasi-Likelihood Information Criteria` (PDF pp. 8491–8492); S154 / Chapter 104 / `Quantile Process Regression` (PDF pp. 8494–8495); S154 / Chapter 104 / `Observation Quantile Level` (PDF p. 8495).

## Scope

Implement Quasi-Likelihood Information Criteria; Quantile Process Regression; Observation Quantile Level. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Quasi-Likelihood Information Criteria / Quantile Process Regression / Observation Quantile Level, verify the requested quantiles, objective function, tie-breaking rules, and inference; cover extreme quantiles and rank-deficient designs; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: QUANTSELECT Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
