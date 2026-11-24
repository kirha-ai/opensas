# STAT-BCHOICE-008 — BCHOICE — Gamerman Algorithm / Tuning the Random Walk Metropolis in Logit Models / Autocall Macros for Postprocessing

## Source

S154 / Chapter 30 / `Gamerman Algorithm` (PDF pp. 1216–1218); S154 / Chapter 30 / `Tuning the Random Walk Metropolis in Logit Models` (PDF pp. 1218–1220); S154 / Chapter 30 / `Autocall Macros for Postprocessing` (PDF pp. 1220–1222).

## Scope

Implement Gamerman Algorithm; Tuning the Random Walk Metropolis in Logit Models; Autocall Macros for Postprocessing. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Gamerman Algorithm / Tuning the Random Walk Metropolis in Logit Models / Autocall Macros for Postprocessing, use fixed seeds to verify reproducibility and sample dimensions; verify prior support, chain initial values, and posterior summaries; validate distributions against analytic or trusted references and report Monte Carlo error rather than checking a single random draw.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 30.2: Nested Logit Modeling |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
