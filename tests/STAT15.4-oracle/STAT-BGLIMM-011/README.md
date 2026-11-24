# STAT-BGLIMM-011 — BGLIMM — Hamiltonian Monte Carlo Sampler

## Source

S154 / Chapter 31 / `Hamiltonian Monte Carlo Sampler` (PDF pp. 1317–1318).

## Scope

Implement Hamiltonian Monte Carlo Sampler. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Hamiltonian Monte Carlo Sampler, verify resampling units, replicate counts, fixed-seed reproducibility, successful replicate counts, and failed-replicate handling; validate intervals/probabilities against enumerated or error-bounded references.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: BGLIMM Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
