# STAT-PLM-003 — PLM — FILTER / SHOW / WHERE

## Source

S154 / Chapter 94 / `FILTER Statement` (PDF pp. 7635–7636); S154 / Chapter 94 / `SHOW Statement` (PDF pp. 7641–7643); S154 / Chapter 94 / `WHERE Statement` (PDF pp. 7644–7646).

## Scope

Implement FILTER; SHOW; WHERE. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For FILTER / SHOW / WHERE, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: PLM Procedure; explicit statements: SHOW |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: SHOW. Remaining statement variants: FILTER, WHERE.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
