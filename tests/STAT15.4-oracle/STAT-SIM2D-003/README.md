# STAT-SIM2D-003 — SIM2D — COORDINATES / GRID / RESTORE

## Source

S154 / Chapter 112 / `COORDINATES Statement` (PDF pp. 9322–9323); S154 / Chapter 112 / `GRID Statement` (PDF pp. 9323–9326); S154 / Chapter 112 / `RESTORE Statement` (PDF pp. 9326–9328).

## Scope

Implement COORDINATES; GRID; RESTORE. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For COORDINATES / GRID / RESTORE, verify target distributions, units, design constraints, output identifiers, and fixed-seed reproducibility for sampling, randomization, or simulation; enumerate designs to validate inclusion probabilities/combinations, and check simulated distributions using analytic moments and Monte Carlo error bounds.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: SIM2D Procedure; explicit statements: COORDINATES, GRID |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: COORDINATES, GRID. Remaining statement variants: RESTORE. Removed an unrelated animal-data fragment sharing the output name SIM. Uses 100 seeded realizations on a 5-by-5 grid instead of the large illustrative simulation.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
