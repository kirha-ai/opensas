# STAT-RMSTREG-003 — RMSTREG — CLASS / MODEL / Specification of Effects

## Source

S154 / Chapter 106 / `CLASS Statement` (PDF pp. 8737–8741); S154 / Chapter 106 / `MODEL Statement` (PDF pp. 8745–8747); S154 / Chapter 106 / `Specification of Effects` (PDF pp. 8750–8751).

## Scope

Implement CLASS; MODEL; Specification of Effects. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For CLASS / MODEL / Specification of Effects, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: MODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: MODEL. Remaining statement variants: CLASS.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
