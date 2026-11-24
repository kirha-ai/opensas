# STAT-STDIZE-004 — STDIZE — Computation of the Statistics / Computing Quantiles / Constant Data

## Source

S154 / Chapter 115 / `Computation of the Statistics` (PDF pp. 9466–9467); S154 / Chapter 115 / `Computing Quantiles` (PDF pp. 9467–9468); S154 / Chapter 115 / `Constant Data` (PDF pp. 9468–9469).

## Scope

Implement Computation of the Statistics; Computing Quantiles; Constant Data. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Computation of the Statistics / Computing Quantiles / Constant Data, verify the requested quantiles, objective function, tie-breaking rules, and inference; cover extreme quantiles and rank-deficient designs; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: STDIZE Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
