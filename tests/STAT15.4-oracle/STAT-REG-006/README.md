# STAT-REG-006 — REG — Parameter Estimates and Associated Statistics / Models of Less Than Full Rank / Computational Methods

## Source

S154 / Chapter 105 / `Parameter Estimates and Associated Statistics` (PDF pp. 8617–8619); S154 / Chapter 105 / `Models of Less Than Full Rank` (PDF pp. 8623–8624); S154 / Chapter 105 / `Computational Methods` (PDF pp. 8649–8650).

## Scope

Implement Parameter Estimates and Associated Statistics; Models of Less Than Full Rank; Computational Methods. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Parameter Estimates and Associated Statistics / Models of Less Than Full Rank / Computational Methods, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: REG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
