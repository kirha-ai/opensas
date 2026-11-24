# STAT-PSMATCH-007 — PSMATCH — Matching Metrics / Matching Methods / Variable Balance Assessment

## Source

S154 / Chapter 101 / `Matching Metrics` (PDF pp. 8245–8246); S154 / Chapter 101 / `Matching Methods` (PDF pp. 8246–8248); S154 / Chapter 101 / `Variable Balance Assessment` (PDF pp. 8250–8253).

## Scope

Implement Matching Metrics; Matching Methods; Variable Balance Assessment. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Matching Metrics / Matching Methods / Variable Balance Assessment, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
