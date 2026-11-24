# STAT-LIFETEST-002 — LIFETEST — Nonparametric survival distributions and group comparisons

## Source

S154 / Chapter 77 / `Getting Started: LIFETEST Procedure` (PDF pp. 5641–5649); S154 / Chapter 77 / `Overview: LIFETEST Procedure` (PDF pp. 5640–5641).

## Scope

Implement nonparametric survival distributions and group comparisons using the documented default path and establish the computational state needed by later extensions; implement specialized models, methods, and diagnostics outside that default example in their corresponding feature tickets.

## Acceptance criteria

Turn the smallest default analysis in Getting Started into a runnable case and verify its principal estimates, observation counts, and result status; add a smaller case with an independent manual calculation; meet the precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_default.sas](documented_default.sas) | captured | 0 | [listing](documented_default.expected.txt) / [log](documented_default.oracle.log) | Documented default analysis with explicit complete public or synthetic inputs |

**documented_default:** Adapted to remove PDF ellipses, typesetting fragments, or external setup; inputs and executed options are explicit in the program. This is not a claim of option-complete coverage.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
