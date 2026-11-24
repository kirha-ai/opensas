# STAT-NLMIXED-014 — NLMIXED — Programming Statements

## Source

S154 / Chapter 89 / `Programming Statements` (PDF pp. 7126–7128).

## Scope

Implement Programming Statements. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For Programming Statements, cover valid boundaries, initial values, scope, and programming evaluation order as applicable; verify objective functions, constraint satisfaction, and stopping status; diagnose invalid settings.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
