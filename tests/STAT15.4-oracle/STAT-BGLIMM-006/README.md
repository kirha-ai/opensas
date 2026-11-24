# STAT-BGLIMM-006 — BGLIMM — RANDOM / GLMM with Random Effects / Treatment of Subjects in the RANDOM

## Source

S154 / Chapter 31 / `RANDOM Statement` (PDF pp. 1294–1305); S154 / Chapter 31 / `GLMM with Random Effects` (PDF pp. 1314–1315); S154 / Chapter 31 / `Treatment of Subjects in the RANDOM Statement` (PDF pp. 1321–1322).

## Scope

Implement RANDOM; GLMM with Random Effects; Treatment of Subjects in the RANDOM. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For RANDOM / GLMM with Random Effects / Treatment of Subjects in the RANDOM, use small models to verify covariance structures, subject/group indices, variance parameters, and applicable predictions/inference; cover repeated times, boundary variances, and nonidentifiable configurations.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: BGLIMM Procedure; explicit statements: RANDOM |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: RANDOM. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
