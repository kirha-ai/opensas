# STAT-CAUSALMED-003 — CAUSALMED — CLASS / COVAR / MEDIATOR

## Source

S154 / Chapter 38 / `CLASS Statement` (PDF pp. 2382–2384); S154 / Chapter 38 / `COVAR Statement` (PDF p. 2384); S154 / Chapter 38 / `MEDIATOR Statement` (PDF pp. 2388–2389).

## Scope

Implement CLASS; COVAR; MEDIATOR. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For CLASS / COVAR / MEDIATOR, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 38.3: Smoking Effect on Infant Mortality; explicit statements: CLASS, COVAR, MEDIATOR |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, COVAR, MEDIATOR. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
