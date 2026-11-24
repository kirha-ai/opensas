# STAT-NPAR1WAY-007 — NPAR1WAY — Multiple Comparisons Based on Pairwise Rankings

## Source

S154 / Chapter 90 / `Multiple Comparisons Based on Pairwise Rankings` (PDF p. 7247).

## Scope

Implement Multiple Comparisons Based on Pairwise Rankings. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Multiple Comparisons Based on Pairwise Rankings, verify estimation functions, standard errors, degrees of freedom, intervals, and adjusted comparisons; use unbalanced designs and missing cells to check estimability and weighting, retaining nonestimable status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: NPAR1WAY Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
