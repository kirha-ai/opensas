# STAT-PLAN-004 — PLAN — TREATMENTS / Using PROC PLAN Interactively / Specifying Factor Structures

## Source

S154 / Chapter 93 / `TREATMENTS Statement` (PDF pp. 7594–7595); S154 / Chapter 93 / `Using PROC PLAN Interactively` (PDF p. 7595); S154 / Chapter 93 / `Specifying Factor Structures` (PDF pp. 7597–7599).

## Scope

Implement TREATMENTS; Using PROC PLAN Interactively; Specifying Factor Structures. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For TREATMENTS / Using PROC PLAN Interactively / Specifying Factor Structures, verify target distributions, units, design constraints, output identifiers, and fixed-seed reproducibility for sampling, randomization, or simulation; enumerate designs to validate inclusion probabilities/combinations, and check simulated distributions using analytic moments and Monte Carlo error bounds.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: PLAN Procedure; explicit statements: TREATMENTS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: TREATMENTS. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
