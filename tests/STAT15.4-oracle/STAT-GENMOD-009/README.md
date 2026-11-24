# STAT-GENMOD-009 — GENMOD — BAYES / Bayesian Analysis

## Source

S154 / Chapter 51 / `BAYES Statement` (PDF pp. 3515–3525); S154 / Chapter 51 / `Bayesian Analysis` (PDF pp. 3607–3612).

## Scope

Implement BAYES; Bayesian Analysis. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For BAYES / Bayesian Analysis, use fixed seeds to verify reproducibility and sample dimensions; verify prior support, chain initial values, and posterior summaries; validate distributions against analytic or trusted references and report Monte Carlo error rather than checking a single random draw.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |
| [targeted_statements.sas](targeted_statements.sas) | captured | 0 | [listing](targeted_statements.expected.txt) / [log](targeted_statements.oracle.log) | Explicit BAYES statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BAYES.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
