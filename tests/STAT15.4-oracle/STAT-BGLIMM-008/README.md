# STAT-BGLIMM-008 — BGLIMM — Gamerman Algorithm / Prior for the Fixed-Effects Coefficients / Prior for the Random-Effects Coefficients

## Source

S154 / Chapter 31 / `Gamerman Algorithm` (PDF pp. 1316–1317); S154 / Chapter 31 / `Prior for the Fixed-Effects Coefficients` (PDF pp. 1318–1319); S154 / Chapter 31 / `Prior for the Random-Effects Coefficients` (PDF p. 1319).

## Scope

Implement Gamerman Algorithm; Prior for the Fixed-Effects Coefficients; Prior for the Random-Effects Coefficients. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Gamerman Algorithm / Prior for the Fixed-Effects Coefficients / Prior for the Random-Effects Coefficients, use fixed seeds to verify reproducibility and sample dimensions; verify prior support, chain initial values, and posterior summaries; validate distributions against analytic or trusted references and report Monte Carlo error rather than checking a single random draw.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: BGLIMM Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
