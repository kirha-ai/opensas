# STAT-QUANTREG-012 — QUANTREG — PERFORMANCE / Computational Resources

## Source

S154 / Chapter 103 / `PERFORMANCE Statement` (PDF pp. 8391–8392); S154 / Chapter 103 / `Computational Resources` (PDF p. 8415).

## Scope

Implement PERFORMANCE; Computational Resources. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For PERFORMANCE / Computational Resources, verify that requests take effect, documented restrictions hold, and results remain equivalent; resource information requires reproducible input and measurement evidence; explicitly diagnose unsupported execution modes.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |
| [statement_performance.sas](statement_performance.sas) | captured | 0 | [listing](statement_performance.expected.txt) / [log](statement_performance.oracle.log) | Explicit single-thread performance settings with the documented baseline computation. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: PERFORMANCE. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax.

**statement_performance:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
