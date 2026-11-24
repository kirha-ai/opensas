# STAT-COMMON-015 — Survival data and censoring contracts

## Source

S154 / Chapter 14 / `Introduction to Survival Analysis Procedures` (PDF pp. 255–262).

## Scope

Establish shared representations of event times, censoring statuses, strata, and survival results; enable left truncation, interval censoring, and competing risks only where supported by the corresponding PROC tickets.

## Acceptance criteria

Use small stratified samples with coincident events/censoring and all-censored observations to verify event counts; reject encodings incompatible with the procedure and distinguish censoring types.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [censoring_risk_sets.sas](censoring_risk_sets.sas) | captured | 0 | [listing](censoring_risk_sets.expected.txt) / [log](censoring_risk_sets.oracle.log) | Event/censoring ties, stratum boundaries and survival result contract |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
