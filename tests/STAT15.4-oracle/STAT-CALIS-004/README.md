# STAT-CALIS-004 — CALIS — COV / MEAN / PCOV / PVAR / STD / VARIANCE

## Source

S154 / Chapter 33 / `COV Statement` (PDF pp. 1544–1549); S154 / Chapter 33 / `MEAN Statement` (PDF pp. 1602–1605); S154 / Chapter 33 / `PCOV Statement` (PDF pp. 1638–1641); S154 / Chapter 33 / `PVAR Statement` (PDF pp. 1641–1643); S154 / Chapter 33 / `STD Statement` (PDF p. 1653); S154 / Chapter 33 / `VARIANCE Statement` (PDF pp. 1657–1661).

## Scope

Implement COV; MEAN; PCOV; PVAR; STD; VARIANCE. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For COV / MEAN / PCOV / PVAR / STD / VARIANCE, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 33.11: Measurement Error Models Specified as Linear Equations; explicit statements: COV, MEAN, PCOV, PVAR, VARIANCE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: COV, MEAN, PCOV, PVAR, VARIANCE. Remaining statement variants: STD. Restored the blank _NAME_ field on the MEAN row and converted the extracted covariance rows to list input.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
