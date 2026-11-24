# STAT-SURVEYLOGISTIC-003 — SURVEYLOGISTIC — CLASS / EFFECT / MODEL

## Source

S154 / Chapter 120 / `CLASS Statement` (PDF pp. 9812–9814); S154 / Chapter 120 / `EFFECT Statement` (PDF pp. 9818–9819); S154 / Chapter 120 / `MODEL Statement` (PDF pp. 9823–9831).

## Scope

Implement CLASS; EFFECT; MODEL. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For CLASS / EFFECT / MODEL, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 120.1: Stratified Sampling; explicit statements: CLASS, MODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, MODEL. Remaining statement variants: EFFECT. Restored the official Class format from physical PDF page 9883.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
