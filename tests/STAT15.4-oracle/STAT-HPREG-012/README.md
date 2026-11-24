# STAT-HPREG-012 — HPREG — PERFORMANCE

## Source

S154 / Chapter 67 / `PERFORMANCE Statement` (PDF pp. 5035–5036).

## Scope

Implement PERFORMANCE. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For PERFORMANCE, verify that requests take effect, documented restrictions hold, and results remain equivalent; resource information requires reproducible input and measurement evidence; explicitly diagnose unsupported execution modes.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 67.3: Forward Selection with Screening; explicit statements: PERFORMANCE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PERFORMANCE. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
