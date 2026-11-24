# STAT-HPFMM-003 — HPFMM — CLASS / MODEL / PROBMODEL

## Source

S154 / Chapter 58 / `CLASS Statement` (PDF p. 4554); S154 / Chapter 58 / `MODEL Statement` (PDF pp. 4555–4563); S154 / Chapter 58 / `PROBMODEL Statement` (PDF pp. 4566–4568).

## Scope

Implement CLASS; MODEL; PROBMODEL. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For CLASS / MODEL / PROBMODEL, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 58.1: Modeling Mixing Probabilities: All Mice Are Equal, but Some Mice Are More Equal Than Others; explicit statements: CLASS, MODEL, PROBMODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, MODEL, PROBMODEL. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
