# STAT-PROBIT-003 — PROBIT — CLASS / MODEL / Response Level Ordering

## Source

S154 / Chapter 100 / `CLASS Statement` (PDF pp. 8106–8108); S154 / Chapter 100 / `MODEL Statement` (PDF pp. 8112–8118); S154 / Chapter 100 / `Response Level Ordering` (PDF pp. 8120–8122).

## Scope

Implement CLASS; MODEL; Response Level Ordering. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For CLASS / MODEL / Response Level Ordering, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 100.2: Multilevel Response; explicit statements: CLASS, MODEL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, MODEL. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
