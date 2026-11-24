# STAT-GENMOD-005 — GENMOD — DEVIANCE / Generalized Linear Models Theory / Multinomial Models

## Source

S154 / Chapter 51 / `DEVIANCE Statement` (PDF pp. 3532–3533); S154 / Chapter 51 / `Generalized Linear Models Theory` (PDF pp. 3568–3579); S154 / Chapter 51 / `Multinomial Models` (PDF pp. 3587–3588).

## Scope

Implement DEVIANCE; Generalized Linear Models Theory; Multinomial Models. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For DEVIANCE / Generalized Linear Models Theory / Multinomial Models, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 51.4: Ordinal Model for Multinomial Data |
| [targeted_statements.sas](targeted_statements.sas) | captured | 0 | [listing](targeted_statements.expected.txt) / [log](targeted_statements.oracle.log) | Explicit DEVIANCE, VARIANCE statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: DEVIANCE.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
