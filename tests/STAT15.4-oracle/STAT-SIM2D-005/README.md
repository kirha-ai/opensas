# STAT-SIM2D-005 — SIM2D — Theoretical Development / Computational Details

## Source

S154 / Chapter 112 / `Theoretical Development` (PDF pp. 9338–9341); S154 / Chapter 112 / `Computational Details` (PDF pp. 9341–9342).

## Scope

Implement Theoretical Development; Computational Details. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Theoretical Development / Computational Details, verify target distributions, units, design constraints, output identifiers, and fixed-seed reproducibility for sampling, randomization, or simulation; enumerate designs to validate inclusion probabilities/combinations, and check simulated distributions using analytic moments and Monte Carlo error bounds.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: SIM2D Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Removed an unrelated animal-data fragment sharing the output name SIM. Uses 100 seeded realizations on a 5-by-5 grid instead of the large illustrative simulation.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
