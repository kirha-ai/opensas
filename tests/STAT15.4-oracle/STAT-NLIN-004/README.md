# STAT-NLIN-004 — NLIN — CONTROL / PROFILE / RETAIN

## Source

S154 / Chapter 88 / `CONTROL Statement` (PDF p. 7002); S154 / Chapter 88 / `PROFILE Statement` (PDF pp. 7011–7012); S154 / Chapter 88 / `RETAIN Statement` (PDF pp. 7012–7013).

## Scope

Implement CONTROL; PROFILE; RETAIN. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For CONTROL / PROFILE / RETAIN, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 88.7: Parameter Profiling and Bootstrapping; explicit statements: PROFILE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PROFILE. Remaining statement variants: CONTROL, RETAIN.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
