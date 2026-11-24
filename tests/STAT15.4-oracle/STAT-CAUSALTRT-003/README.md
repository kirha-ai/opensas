# STAT-CAUSALTRT-003 — CAUSALTRT — CLASS / MODEL / PSMODEL

## Source

S154 / Chapter 39 / `CLASS Statement` (PDF pp. 2448–2450); S154 / Chapter 39 / `MODEL Statement` (PDF pp. 2450–2454); S154 / Chapter 39 / `PSMODEL Statement` (PDF pp. 2455–2459).

## Scope

Implement CLASS; MODEL; PSMODEL. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For CLASS / MODEL / PSMODEL, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: CAUSALTRT Procedure; explicit statements: CLASS, MODEL, PSMODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, MODEL, PSMODEL. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
