# STAT-PHREG-013 — PHREG — BAYES / Specifics for Bayesian Analysis

## Source

S154 / Chapter 92 / `BAYES Statement` (PDF pp. 7341–7355); S154 / Chapter 92 / `Specifics for Bayesian Analysis` (PDF pp. 7455–7466).

## Scope

Implement BAYES; Specifics for Bayesian Analysis. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For BAYES / Specifics for Bayesian Analysis, use fixed seeds to verify reproducibility and sample dimensions; verify prior support, chain initial values, and posterior summaries; validate distributions against analytic or trusted references and report Monte Carlo error rather than checking a single random draw.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 92.14: Bayesian Analysis of Piecewise Exponential Model; explicit statements: BAYES |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: BAYES. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
