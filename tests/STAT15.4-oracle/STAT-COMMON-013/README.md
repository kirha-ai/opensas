# STAT-COMMON-013 — Bayesian priors and posterior summary contracts

## Source

S154 / Chapter 8 / `Prior Distributions` (PDF pp. 152–154); S154 / Chapter 8 / `Bayesian Inference` (PDF pp. 154–156); S154 / Chapter 8 / `Summary Statistics` (PDF pp. 177–180); S154 / Chapter 7 / `Introduction to Mixed Modeling Procedures` (PDF pp. 135–148).

## Scope

Establish shared interfaces for prior support, posterior samples, quantiles, and credible intervals; individual models own their prior families and parameterizations.

## Acceptance criteria

Use analytic posteriors of conjugate models to verify means, variances, and intervals; check improper priors and support violations; report sampling error.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [normal_posterior.sas](normal_posterior.sas) | captured | 0 | [listing](normal_posterior.expected.txt) / [log](normal_posterior.oracle.log) | Normal posterior sampling, fixed seed, retained sample count and posterior/chain summaries |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
