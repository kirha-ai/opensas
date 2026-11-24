# STAT-CATMOD-003 — CATMOD — DIRECT / FACTORS / LOGLIN

## Source

S154 / Chapter 36 / `DIRECT Statement` (PDF pp. 2196–2197); S154 / Chapter 36 / `FACTORS Statement` (PDF pp. 2197–2200); S154 / Chapter 36 / `LOGLIN Statement` (PDF pp. 2200–2201).

## Scope

Implement DIRECT; FACTORS; LOGLIN. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For DIRECT / FACTORS / LOGLIN, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 36.10: Direct Input of Response Functions and Covariance Matrix; explicit statements: FACTORS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: FACTORS. Remaining statement variants: DIRECT, LOGLIN.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
