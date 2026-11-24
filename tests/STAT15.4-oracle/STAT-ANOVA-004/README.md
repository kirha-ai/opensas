# STAT-ANOVA-004 — ANOVA — ABSORB / Using PROC ANOVA Interactively / Computational Method

## Source

S154 / Chapter 29 / `ABSORB Statement` (PDF p. 1117); S154 / Chapter 29 / `Using PROC ANOVA Interactively` (PDF p. 1138); S154 / Chapter 29 / `Computational Method` (PDF p. 1140).

## Scope

Implement ABSORB; Using PROC ANOVA Interactively; Computational Method. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For ABSORB / Using PROC ANOVA Interactively / Computational Method, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: ANOVA Procedure |
| [targeted_statements.sas](targeted_statements.sas) | captured | 0 | [listing](targeted_statements.expected.txt) / [log](targeted_statements.oracle.log) | Explicit ABSORB statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: ABSORB.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
