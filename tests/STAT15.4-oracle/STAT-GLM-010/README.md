# STAT-GLM-010 — GLM — REPEATED / Repeated Measures Analysis of Variance

## Source

S154 / Chapter 53 / `REPEATED Statement` (PDF pp. 4100–4104); S154 / Chapter 53 / `Repeated Measures Analysis of Variance` (PDF pp. 4149–4157).

## Scope

Implement REPEATED; Repeated Measures Analysis of Variance. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For REPEATED / Repeated Measures Analysis of Variance, use small models to verify covariance structures, subject/group indices, variance parameters, and applicable predictions/inference; cover repeated times, boundary variances, and nonidentifiable configurations.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 53.7: Repeated Measures Analysis of Variance; explicit statements: REPEATED |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: REPEATED. Remaining statement variants: . Converted the extracted fixed-width drug field to list input; the measurements remain from the official example.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
