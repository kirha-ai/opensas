# STAT-SURVEYLOGISTIC-004 — SURVEYLOGISTIC — Response Level Ordering / CLASS Variable Parameterization

## Source

S154 / Chapter 120 / `Response Level Ordering` (PDF pp. 9840–9841); S154 / Chapter 120 / `CLASS Variable Parameterization` (PDF pp. 9841–9844).

## Scope

Implement Response Level Ordering; CLASS Variable Parameterization. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For Response Level Ordering / CLASS Variable Parameterization, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
