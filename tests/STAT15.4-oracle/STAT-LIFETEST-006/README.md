# STAT-LIFETEST-006 — LIFETEST — Restricted Mean Analysis

## Source

S154 / Chapter 77 / `Restricted Mean Analysis` (PDF pp. 5690–5692).

## Scope

Implement Restricted Mean Analysis. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For Restricted Mean Analysis, cover valid boundaries, initial values, scope, and programming evaluation order as applicable; verify objective functions, constraint satisfaction, and stopping status; diagnose invalid settings.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: LIFETEST Procedure |
| [restricted_means.sas](restricted_means.sas) | captured | 0 | [listing](restricted_means.expected.txt) / [log](restricted_means.oracle.log) | Restricted mean survival time and restricted mean time lost at an explicit tau of 6. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Restored the official treatment format from physical PDF page 5642.

**restricted_means:** Small synthetic input with explicit truncation time. Inspect RMST/RMTL estimates and group comparisons, not just ordinary survival tables.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
