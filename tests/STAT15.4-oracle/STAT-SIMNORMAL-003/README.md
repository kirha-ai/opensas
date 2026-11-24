# STAT-SIMNORMAL-003 — SIMNORMAL — CONDITION / Introduction / Unconditional Simulation

## Source

S154 / Chapter 113 / `CONDITION Statement` (PDF pp. 9369–9370); S154 / Chapter 113 / `Introduction` (PDF pp. 9370–9371); S154 / Chapter 113 / `Unconditional Simulation` (PDF pp. 9371–9372).

## Scope

Implement CONDITION; Introduction; Unconditional Simulation. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For CONDITION / Introduction / Unconditional Simulation, verify target distributions, units, design constraints, output identifiers, and fixed-seed reproducibility for sampling, randomization, or simulation; enumerate designs to validate inclusion probabilities/combinations, and check simulated distributions using analytic moments and Monte Carlo error bounds.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: CONDITION.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
