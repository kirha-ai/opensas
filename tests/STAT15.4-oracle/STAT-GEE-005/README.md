# STAT-GEE-005 — GEE — REPEATED / Generalized Estimating Equations / Alternating Logistic Regression

## Source

S154 / Chapter 50 / `REPEATED Statement` (PDF pp. 3439–3443); S154 / Chapter 50 / `Generalized Estimating Equations` (PDF pp. 3444–3448); S154 / Chapter 50 / `Alternating Logistic Regression` (PDF pp. 3448–3452).

## Scope

Implement REPEATED; Generalized Estimating Equations; Alternating Logistic Regression. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For REPEATED / Generalized Estimating Equations / Alternating Logistic Regression, use small models to verify covariance structures, subject/group indices, variance parameters, and applicable predictions/inference; cover repeated times, boundary variances, and nonidentifiable configurations.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started; explicit statements: REPEATED |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: REPEATED. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
