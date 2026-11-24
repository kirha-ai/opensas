# STAT-MCMC-014 — MCMC — PRIOR/HYPERPRIOR / How PROC MCMC Works / Sampling Methods

## Source

S154 / Chapter 80 / `PRIOR/HYPERPRIOR Statement` (PDF pp. 6134–6135); S154 / Chapter 80 / `How PROC MCMC Works` (PDF pp. 6146–6149); S154 / Chapter 80 / `Sampling Methods` (PDF pp. 6151–6152).

## Scope

Implement PRIOR/HYPERPRIOR; How PROC MCMC Works; Sampling Methods. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For PRIOR/HYPERPRIOR / How PROC MCMC Works / Sampling Methods, use fixed seeds to verify reproducibility and sample dimensions; verify prior support, chain initial values, and posterior summaries; validate distributions against analytic or trusted references and report Monte Carlo error rather than checking a single random draw.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 80.4: Logistic Regression Model with Jeffreys' Prior |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
