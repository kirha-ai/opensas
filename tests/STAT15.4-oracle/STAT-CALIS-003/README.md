# STAT-CALIS-003 — CALIS — Classes of Statements in PROC CALIS / Single-Group Analysis Syntax / Multiple-Group Multiple-Model Analysis Syntax / GROUP

## Source

S154 / Chapter 33 / `Classes of Statements in PROC CALIS` (PDF pp. 1484–1487); S154 / Chapter 33 / `Single-Group Analysis Syntax` (PDF p. 1487); S154 / Chapter 33 / `Multiple-Group Multiple-Model Analysis Syntax` (PDF pp. 1487–1488); S154 / Chapter 33 / `GROUP Statement` (PDF pp. 1565–1568).

## Scope

Implement Classes of Statements in PROC CALIS; Single-Group Analysis Syntax; Multiple-Group Multiple-Model Analysis Syntax; GROUP. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For Classes of Statements in PROC CALIS / Single-Group Analysis Syntax / Multiple-Group Multiple-Model Analysis Syntax / GROUP, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 33.21: Testing Equality of Two Covariance Matrices Using a Multiple-Group Analysis; explicit statements: GROUP |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: GROUP. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
