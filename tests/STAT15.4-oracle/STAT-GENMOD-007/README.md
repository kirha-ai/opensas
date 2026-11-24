# STAT-GENMOD-007 — GENMOD — REPEATED / Generalized Estimating Equations

## Source

S154 / Chapter 51 / `REPEATED Statement` (PDF pp. 3560–3565); S154 / Chapter 51 / `Generalized Estimating Equations` (PDF pp. 3591–3600).

## Scope

Implement REPEATED; Generalized Estimating Equations. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For REPEATED / Generalized Estimating Equations, use small models to verify covariance structures, subject/group indices, variance parameters, and applicable predictions/inference; cover repeated times, boundary variances, and nonidentifiable configurations.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 51.5: GEE for Binary Data with Logit Link Function; explicit statements: REPEATED |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: REPEATED. Remaining statement variants: . The manual refers to an external full response data set; this fixture supplies explicit seeded synthetic subjects before wide-to-long conversion.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
