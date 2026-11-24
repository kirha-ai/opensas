# STAT-CATMOD-004 — CATMOD — MODEL / RESPONSE / Specification of Effects

## Source

S154 / Chapter 36 / `MODEL Statement` (PDF pp. 2201–2208); S154 / Chapter 36 / `RESPONSE Statement` (PDF pp. 2212–2219); S154 / Chapter 36 / `Specification of Effects` (PDF pp. 2224–2226).

## Scope

Implement MODEL; RESPONSE; Specification of Effects. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For MODEL / RESPONSE / Specification of Effects, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 36.1: Linear Response Function, r=2 Responses; explicit statements: MODEL, RESPONSE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: MODEL, RESPONSE. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
