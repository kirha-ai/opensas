# STAT-GLM-005 — GLM — ABSORB / Statistical Assumptions for Using PROC GLM / Using PROC GLM Interactively

## Source

S154 / Chapter 53 / `ABSORB Statement` (PDF p. 4065); S154 / Chapter 53 / `Statistical Assumptions for Using PROC GLM` (PDF pp. 4106–4107); S154 / Chapter 53 / `Using PROC GLM Interactively` (PDF p. 4110).

## Scope

Implement ABSORB; Statistical Assumptions for Using PROC GLM; Using PROC GLM Interactively. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For ABSORB / Statistical Assumptions for Using PROC GLM / Using PROC GLM Interactively, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: GLM Procedure |
| [targeted_statements.sas](targeted_statements.sas) | captured | 0 | [listing](targeted_statements.expected.txt) / [log](targeted_statements.oracle.log) | Explicit ABSORB statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: ABSORB.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
