# STAT-BGLIMM-007 — BGLIMM — REPEATED

## Source

S154 / Chapter 31 / `REPEATED Statement` (PDF pp. 1305–1308).

## Scope

Implement REPEATED. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For REPEATED, use small models to verify covariance structures, subject/group indices, variance parameters, and applicable predictions/inference; cover repeated times, boundary variances, and nonidentifiable configurations.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 31.4: Repeated Growth Measurements with Group Difference; explicit statements: REPEATED |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: REPEATED. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. Removed an isolated illustrative MODEL statement outside PROC; retained the complete REPEATED models.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
