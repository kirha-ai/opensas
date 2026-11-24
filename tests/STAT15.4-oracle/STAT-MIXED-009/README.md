# STAT-MIXED-009 — MIXED — CONTRAST / ESTIMATE

## Source

S154 / Chapter 84 / `CONTRAST Statement` (PDF pp. 6640–6643); S154 / Chapter 84 / `ESTIMATE Statement` (PDF pp. 6643–6645).

## Scope

Implement CONTRAST; ESTIMATE. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For CONTRAST / ESTIMATE, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 84.1: Split-Plot Design; explicit statements: ESTIMATE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: ESTIMATE. Remaining statement variants: CONTRAST.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
