# STAT-CATMOD-009 — CATMOD — REPEATED / Repeated Measures Analysis

## Source

S154 / Chapter 36 / `REPEATED Statement` (PDF pp. 2211–2212); S154 / Chapter 36 / `Repeated Measures Analysis` (PDF pp. 2232–2234).

## Scope

Implement REPEATED; Repeated Measures Analysis. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For REPEATED / Repeated Measures Analysis, use small models to verify covariance structures, subject/group indices, variance parameters, and applicable predictions/inference; cover repeated times, boundary variances, and nonidentifiable configurations.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 36.6: Repeated Measures, 2 Response Levels, 3 Populations; explicit statements: REPEATED |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: REPEATED. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
