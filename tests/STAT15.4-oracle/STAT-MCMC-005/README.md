# STAT-MCMC-005 — MCMC — CMPTMODEL / UDS / Blocking of Parameters

## Source

S154 / Chapter 80 / `CMPTMODEL Statement` (PDF pp. 6120–6123); S154 / Chapter 80 / `UDS Statement` (PDF pp. 6145–6146); S154 / Chapter 80 / `Blocking of Parameters` (PDF pp. 6149–6151).

## Scope

Implement CMPTMODEL; UDS; Blocking of Parameters. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For CMPTMODEL / UDS / Blocking of Parameters, verify target log densities, parameter support, and the relevant sampling/summary steps; check fixed-seed reproducibility and posterior moments/intervals against known analytic distributions; record chain diagnostics and Monte Carlo error.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: MCMC Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: CMPTMODEL, UDS. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
