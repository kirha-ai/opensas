# STAT-FREQ-014 — FREQ — Cochran-Mantel-Haenszel Statistics

## Source

S154 / Chapter 47 / `Cochran-Mantel-Haenszel Statistics` (PDF pp. 3223–3233).

## Scope

Implement Cochran-Mantel-Haenszel Statistics. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Cochran-Mantel-Haenszel Statistics, use manually calculated stratified tables to verify stratum scores, CMH statistics, degrees of freedom, and probabilities; include degenerate strata; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 47.7: Cochran-Mantel-Haenszel Statistics |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
