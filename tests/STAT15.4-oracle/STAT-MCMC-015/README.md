# STAT-MCMC-015 — MCMC — Initial Values of the Markov Chains / Matrix Functions in PROC MCMC / Autocall Macros for Postprocessing

## Source

S154 / Chapter 80 / `Initial Values of the Markov Chains` (PDF pp. 6156–6157); S154 / Chapter 80 / `Matrix Functions in PROC MCMC` (PDF pp. 6182–6186); S154 / Chapter 80 / `Autocall Macros for Postprocessing` (PDF pp. 6212–6215).

## Scope

Implement Initial Values of the Markov Chains; Matrix Functions in PROC MCMC; Autocall Macros for Postprocessing. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Initial Values of the Markov Chains / Matrix Functions in PROC MCMC / Autocall Macros for Postprocessing, use fixed seeds to verify reproducibility and sample dimensions; verify prior support, chain initial values, and posterior summaries; validate distributions against analytic or trusted references and report Monte Carlo error rather than checking a single random draw.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: MCMC Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
