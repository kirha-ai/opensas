# STAT-GLM-003 — GLM — CLASS / MODEL / Specification of Effects

## Source

S154 / Chapter 53 / `CLASS Statement` (PDF pp. 4066–4067); S154 / Chapter 53 / `MODEL Statement` (PDF pp. 4092–4096); S154 / Chapter 53 / `Specification of Effects` (PDF pp. 4107–4110).

## Scope

Implement CLASS; MODEL; Specification of Effects. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For CLASS / MODEL / Specification of Effects, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: GLM Procedure; explicit statements: CLASS, MODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, MODEL. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
