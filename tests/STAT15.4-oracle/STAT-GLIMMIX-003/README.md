# STAT-GLIMMIX-003 — GLIMMIX — Implications of the Non-Full-Rank Parameterization / Intercept / Interaction Effects / Nested Effects / Notes on the EFFECT / Positional and Nonpositional Syntax for Contrast Coefficients

## Source

S154 / Chapter 52 / `Implications of the Non-Full-Rank Parameterization` (PDF p. 3876); S154 / Chapter 52 / `Intercept` (PDF p. 3875); S154 / Chapter 52 / `Interaction Effects` (PDF p. 3875); S154 / Chapter 52 / `Nested Effects` (PDF pp. 3875–3876); S154 / Chapter 52 / `Notes on the EFFECT Statement` (PDF pp. 3876–3878); S154 / Chapter 52 / `Positional and Nonpositional Syntax for Contrast Coefficients` (PDF pp. 3878–3881).

## Scope

Implement Implications of the Non-Full-Rank Parameterization; Intercept; Interaction Effects; Nested Effects; Notes on the EFFECT; Positional and Nonpositional Syntax for Contrast Coefficients. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For Implications of the Non-Full-Rank Parameterization / Intercept / Interaction Effects / Nested Effects / Notes on the EFFECT / Positional and Nonpositional Syntax for Contrast Coefficients, verify the parsed response/effect/parameter representation against the documented design matrix or model structure; cover applicable reference levels, interactions, missing levels, and invalid models; successful parsing alone is insufficient.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 52.11: Maximum Likelihood in Proportional Odds Model with Random Effects |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
