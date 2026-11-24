# STAT-TTEST-006 — TTEST — PAIRED / Paired Design

## Source

S154 / Chapter 128 / `PAIRED Statement` (PDF p. 10617); S154 / Chapter 128 / `Paired Design` (PDF pp. 10623–10624).

## Scope

Implement PAIRED; Paired Design. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For PAIRED / Paired Design, verify paired differences, pairwise missing-value exclusion rules, degrees of freedom, and intervals; reversing pair order must correctly change direction and one-sided probabilities; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [paired_direction.sas](paired_direction.sas) | captured | 0 | [listing](paired_direction.expected.txt) / [log](paired_direction.oracle.log) | Paired differences, reversed direction and one-sided inference |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
