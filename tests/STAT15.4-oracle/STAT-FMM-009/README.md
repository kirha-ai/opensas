# STAT-FMM-009 — FMM — BAYES / Metropolis-Hastings Algorithm / Prior Distributions

## Source

S154 / Chapter 46 / `BAYES Statement` (PDF pp. 2986–2995); S154 / Chapter 46 / `Metropolis-Hastings Algorithm` (PDF pp. 3027–3028); S154 / Chapter 46 / `Prior Distributions` (PDF pp. 3028–3030).

## Scope

Implement BAYES; Metropolis-Hastings Algorithm; Prior Distributions. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For BAYES / Metropolis-Hastings Algorithm / Prior Distributions, use fixed seeds to verify reproducibility and sample dimensions; verify prior support, chain initial values, and posterior summaries; validate distributions against analytic or trusted references and report Monte Carlo error rather than checking a single random draw.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: FMM Procedure; explicit statements: BAYES |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: BAYES. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
