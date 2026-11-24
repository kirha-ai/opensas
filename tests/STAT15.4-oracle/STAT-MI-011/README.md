# STAT-MI-011 — MI — MCMC / MCMC Method for Arbitrary Missing Multivariate Normal Data / Producing Monotone Missingness with the MCMC Method

## Source

S154 / Chapter 82 / `MCMC Statement` (PDF pp. 6436–6440); S154 / Chapter 82 / `MCMC Method for Arbitrary Missing Multivariate Normal Data` (PDF pp. 6467–6471); S154 / Chapter 82 / `Producing Monotone Missingness with the MCMC Method` (PDF pp. 6471–6473).

## Scope

Implement MCMC; MCMC Method for Arbitrary Missing Multivariate Normal Data; Producing Monotone Missingness with the MCMC Method. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For MCMC / MCMC Method for Arbitrary Missing Multivariate Normal Data / Producing Monotone Missingness with the MCMC Method, use fixed seeds to verify reproducibility and sample dimensions; verify prior support, chain initial values, and posterior summaries; validate distributions against analytic or trusted references and report Monte Carlo error rather than checking a single random draw.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 82.10: Producing Monotone Missingness with MCMC; explicit statements: MCMC |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: MCMC. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
