# STAT-ICPHREG-003 — ICPHREG — CLASS / MODEL / Baseline Parameterization

## Source

S154 / Chapter 70 / `CLASS Statement` (PDF pp. 5218–5221); S154 / Chapter 70 / `MODEL Statement` (PDF pp. 5224–5227); S154 / Chapter 70 / `Baseline Parameterization` (PDF pp. 5231–5232).

## Scope

Implement CLASS; MODEL; Baseline Parameterization. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For CLASS / MODEL / Baseline Parameterization, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: ICPHREG Procedure; explicit statements: CLASS, MODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, MODEL. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
