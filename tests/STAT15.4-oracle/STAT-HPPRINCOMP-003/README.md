# STAT-HPPRINCOMP-003 — HPPRINCOMP — PARTIAL / Eigenvalue Decomposition / NIPALS

## Source

S154 / Chapter 65 / `PARTIAL Statement` (PDF pp. 4957–4958); S154 / Chapter 65 / `Eigenvalue Decomposition` (PDF p. 4959); S154 / Chapter 65 / `NIPALS` (PDF p. 4959).

## Scope

Implement PARTIAL; Eigenvalue Decomposition; NIPALS. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For PARTIAL / Eigenvalue Decomposition / NIPALS, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: HPPRINCOMP Procedure |
| [targeted_statements.sas](targeted_statements.sas) | captured | 0 | [listing](targeted_statements.expected.txt) / [log](targeted_statements.oracle.log) | Explicit PARTIAL statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: PARTIAL. Converted state labels to underscore-separated list input, preserving the official missing Murder value for Wyoming.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
