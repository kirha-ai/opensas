# STAT-BGLIMM-009 — BGLIMM — Prior for the G-Side Covariance / Prior for the Scale Parameter / Prior for the R-Side Covariance

## Source

S154 / Chapter 31 / `Prior for the G-Side Covariance` (PDF pp. 1319–1320); S154 / Chapter 31 / `Prior for the Scale Parameter` (PDF pp. 1320–1321); S154 / Chapter 31 / `Prior for the R-Side Covariance` (PDF p. 1321).

## Scope

Implement Prior for the G-Side Covariance; Prior for the Scale Parameter; Prior for the R-Side Covariance. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Prior for the G-Side Covariance / Prior for the Scale Parameter / Prior for the R-Side Covariance, use fixed seeds to verify reproducibility and sample dimensions; verify prior support, chain initial values, and posterior summaries; validate distributions against analytic or trusted references and report Monte Carlo error rather than checking a single random draw.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: BGLIMM Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
