# STAT-COMMON-005 — Shared interfaces for tests, tail probabilities, and confidence intervals

## Source

S154 / Chapter 4 / `Hypothesis Testing and Power` (PDF p. 58); S154 / Chapter 5 / `Testing Linear Hypotheses` (PDF p. 112); S154 / Chapter 5 / `Parameter Estimates and Associated Statistics` (PDF pp. 106–110).

## Scope

Establish shared result conventions for statistics, degrees of freedom, one-/two-sided tail probabilities, and intervals; callers specify distributions and correction formulas from the relevant guide sections.

## Acceptance criteria

Use independent reference values for positive/negative statistics, one-/two-sided conversions, degenerate degrees of freedom, and extreme tails; each caller records absolute/relative tolerances and justification rather than masking tail errors with a broad common tolerance.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [tails_and_intervals.sas](tails_and_intervals.sas) | captured | 0 | [listing](tails_and_intervals.expected.txt) / [log](tails_and_intervals.oracle.log) | Two-sided and directed one-sided probabilities and intervals |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
