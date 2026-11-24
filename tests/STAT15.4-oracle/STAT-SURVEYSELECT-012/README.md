# STAT-SURVEYSELECT-012 — SURVEYSELECT — CONTROL / SAMPLINGUNIT | CLUSTER / Sorting by CONTROL Variables

## Source

S154 / Chapter 124 / `CONTROL Statement` (PDF p. 10235); S154 / Chapter 124 / `SAMPLINGUNIT | CLUSTER Statement` (PDF pp. 10236–10237); S154 / Chapter 124 / `Sorting by CONTROL Variables` (PDF pp. 10244–10245).

## Scope

Implement CONTROL; SAMPLINGUNIT | CLUSTER; Sorting by CONTROL Variables. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For CONTROL / SAMPLINGUNIT | CLUSTER / Sorting by CONTROL Variables, verify target distributions, units, design constraints, output identifiers, and fixed-seed reproducibility for sampling, randomization, or simulation; enumerate designs to validate inclusion probabilities/combinations, and check simulated distributions using analytic moments and Monte Carlo error bounds.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: CONTROL.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
