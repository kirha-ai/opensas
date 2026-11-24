# STAT-SIM2D-004 — SIM2D — SIMULATE / MEAN / Introduction

## Source

S154 / Chapter 112 / `SIMULATE Statement` (PDF pp. 9328–9337); S154 / Chapter 112 / `MEAN Statement` (PDF pp. 9337–9338); S154 / Chapter 112 / `Introduction` (PDF p. 9338).

## Scope

Implement SIMULATE; MEAN; Introduction. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For SIMULATE / MEAN / Introduction, verify target distributions, units, design constraints, output identifiers, and fixed-seed reproducibility for sampling, randomization, or simulation; enumerate designs to validate inclusion probabilities/combinations, and check simulated distributions using analytic moments and Monte Carlo error bounds.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: SIM2D Procedure; explicit statements: SIMULATE, MEAN |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: SIMULATE, MEAN. Remaining statement variants: . Removed an unrelated animal-data fragment sharing the output name SIM. Uses 100 seeded realizations on a 5-by-5 grid instead of the large illustrative simulation.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
