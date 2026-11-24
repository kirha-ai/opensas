# STAT-TPSPLINE-003 — TPSPLINE — MODEL

## Source

S154 / Chapter 125 / `MODEL Statement` (PDF pp. 10303–10306).

## Scope

Implement MODEL. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For MODEL, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: TPSPLINE Procedure; explicit statements: MODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: MODEL. Remaining statement variants: . Routes traditional SAS/GRAPH output to a temporary SVG file in the session, allowing independent replay without server-directory write permissions.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
