# STAT-HPPRINCOMP-008 — HPPRINCOMP — PERFORMANCE

## Source

S154 / Chapter 65 / `PERFORMANCE Statement` (PDF p. 4958).

## Scope

Implement PERFORMANCE. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For PERFORMANCE, verify that requests take effect, documented restrictions hold, and results remain equivalent; resource information requires reproducible input and measurement evidence; explicitly diagnose unsupported execution modes.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: HPPRINCOMP Procedure |
| [statement_performance.sas](statement_performance.sas) | captured | 1 | [listing](statement_performance.expected.txt) / [log](statement_performance.oracle.log) | Explicit single-thread performance settings with the documented baseline computation. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: PERFORMANCE. Converted state labels to underscore-separated list input, preserving the official missing Murder value for Wyoming.

**statement_performance:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions. Converted state labels to underscore-separated list input, preserving the official missing Murder value for Wyoming.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
