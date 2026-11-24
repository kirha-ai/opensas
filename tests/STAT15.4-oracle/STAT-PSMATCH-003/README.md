# STAT-PSMATCH-003 — PSMATCH — PSMODEL

## Source

S154 / Chapter 101 / `PSMODEL Statement` (PDF pp. 8232–8233).

## Scope

Implement PSMODEL. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For PSMODEL, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: PSMODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PSMODEL. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
