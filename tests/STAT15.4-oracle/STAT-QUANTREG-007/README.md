# STAT-QUANTREG-007 — QUANTREG — ESTIMATE / TEST / Confidence Interval

## Source

S154 / Chapter 103 / `ESTIMATE Statement` (PDF pp. 8384–8385); S154 / Chapter 103 / `TEST Statement` (PDF pp. 8392–8393); S154 / Chapter 103 / `Confidence Interval` (PDF pp. 8402–8405).

## Scope

Implement ESTIMATE; TEST; Confidence Interval. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For ESTIMATE / TEST / Confidence Interval, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |
| [targeted_statements.sas](targeted_statements.sas) | captured | 0 | [listing](targeted_statements.expected.txt) / [log](targeted_statements.oracle.log) | Explicit ESTIMATE, TEST statement behavior on seeded synthetic inputs. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: ESTIMATE, TEST. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax.

**targeted_statements:** Small synthetic case authored from this ticket’s statement syntax. This adds a direct observable case; it does not cover every option or failure mode. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax. Native QUANTREG TEST takes model effects; the explicit coefficient combination is requested by ESTIMATE.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
