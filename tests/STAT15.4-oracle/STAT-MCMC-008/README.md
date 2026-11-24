# STAT-MCMC-008 — MCMC — Specifying a New Distribution / Truncation and Censoring / Some Useful SAS Functions

## Source

S154 / Chapter 80 / `Specifying a New Distribution` (PDF pp. 6174–6175); S154 / Chapter 80 / `Truncation and Censoring` (PDF pp. 6178–6180); S154 / Chapter 80 / `Some Useful SAS Functions` (PDF pp. 6180–6182).

## Scope

Implement Specifying a New Distribution; Truncation and Censoring; Some Useful SAS Functions. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Specifying a New Distribution / Truncation and Censoring / Some Useful SAS Functions, verify target log densities, parameter support, and the relevant sampling/summary steps; check fixed-seed reproducibility and posterior moments/intervals against known analytic distributions; record chain diagnostics and Monte Carlo error.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 80.17: Normal Regression with Interval Censoring |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
