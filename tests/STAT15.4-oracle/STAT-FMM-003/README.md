# STAT-FMM-003 — FMM — CLASS / MODEL / PROBMODEL

## Source

S154 / Chapter 46 / `CLASS Statement` (PDF p. 2996); S154 / Chapter 46 / `MODEL Statement` (PDF pp. 2997–3005); S154 / Chapter 46 / `PROBMODEL Statement` (PDF pp. 3009–3011).

## Scope

Implement CLASS; MODEL; PROBMODEL. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For CLASS / MODEL / PROBMODEL, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 46.4: Modeling Multinomial Overdispersion: Town and Country; explicit statements: CLASS, MODEL, PROBMODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, MODEL, PROBMODEL. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
