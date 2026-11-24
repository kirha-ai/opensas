# STAT-CALIS-005 — CALIS — AUXILIARY / MATRIX / RENAMEPARM / VARNAMES

## Source

S154 / Chapter 33 / `AUXILIARY Statement` (PDF pp. 1532–1533); S154 / Chapter 33 / `MATRIX Statement` (PDF pp. 1589–1602); S154 / Chapter 33 / `RENAMEPARM Statement` (PDF pp. 1651–1652); S154 / Chapter 33 / `VARNAMES Statement` (PDF pp. 1661–1662).

## Scope

Implement AUXILIARY; MATRIX; RENAMEPARM; VARNAMES. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For AUXILIARY / MATRIX / RENAMEPARM / VARNAMES, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 33.22: Testing Equality of Covariance and Mean Matrices between Independent Groups; explicit statements: MATRIX, RENAMEPARM |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: MATRIX, RENAMEPARM. Remaining statement variants: AUXILIARY, VARNAMES.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
