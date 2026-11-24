# STAT-CALIS-006 — CALIS — MODEL / Default Analysis Type and Default Parameterization / Naming Variables and Parameters

## Source

S154 / Chapter 33 / `MODEL Statement` (PDF pp. 1605–1607); S154 / Chapter 33 / `Default Analysis Type and Default Parameterization` (PDF pp. 1683–1685); S154 / Chapter 33 / `Naming Variables and Parameters` (PDF pp. 1728–1729).

## Scope

Implement MODEL; Default Analysis Type and Default Parameterization; Naming Variables and Parameters. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For MODEL / Default Analysis Type and Default Parameterization / Naming Variables and Parameters, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 33.33: Longitudinal Factor Analysis; explicit statements: MODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: MODEL. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
