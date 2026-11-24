# STAT-MI-012 — MI — MCMC Method Specifications / Checking Convergence in MCMC

## Source

S154 / Chapter 82 / `MCMC Method Specifications` (PDF pp. 6473–6474); S154 / Chapter 82 / `Checking Convergence in MCMC` (PDF pp. 6474–6476).

## Scope

Implement MCMC Method Specifications; Checking Convergence in MCMC. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For MCMC Method Specifications / Checking Convergence in MCMC, use fixed seeds to verify reproducibility and sample dimensions; verify prior support, chain initial values, and posterior summaries; validate distributions against analytic or trusted references and report Monte Carlo error rather than checking a single random draw.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 82.11: Checking Convergence in MCMC |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
