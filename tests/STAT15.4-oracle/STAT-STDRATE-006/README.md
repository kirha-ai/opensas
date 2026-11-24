# STAT-STDRATE-006 — STDRATE — Applicable Confidence Limits for Rate and Risk Statistics

## Source

S154 / Chapter 116 / `Applicable Confidence Limits for Rate and Risk Statistics` (PDF pp. 9519–9520).

## Scope

Implement Applicable Confidence Limits for Rate and Risk Statistics. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Applicable Confidence Limits for Rate and Risk Statistics, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 116.2: Computing Mantel-Haenszel Risk Estimation |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
