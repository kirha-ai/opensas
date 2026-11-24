# STAT-MCMC-007 — MCMC — Assignments of Parameters / Standard Distributions / Usage of Multivariate Distributions

## Source

S154 / Chapter 80 / `Assignments of Parameters` (PDF pp. 6157–6158); S154 / Chapter 80 / `Standard Distributions` (PDF pp. 6158–6171); S154 / Chapter 80 / `Usage of Multivariate Distributions` (PDF pp. 6171–6174).

## Scope

Implement Assignments of Parameters; Standard Distributions; Usage of Multivariate Distributions. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Assignments of Parameters / Standard Distributions / Usage of Multivariate Distributions, verify target log densities, parameter support, and the relevant sampling/summary steps; check fixed-seed reproducibility and posterior moments/intervals against known analytic distributions; record chain diagnostics and Monte Carlo error.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 80.9: Multivariate Normal Random-Effects Model |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
