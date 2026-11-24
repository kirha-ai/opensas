# STAT-QUANTREG-005 — QUANTREG — Covariance-Correlation / Linear Test / Estimating Probability Functions by Using the CONDDIST

## Source

S154 / Chapter 103 / `Covariance-Correlation` (PDF pp. 8405–8406); S154 / Chapter 103 / `Linear Test` (PDF pp. 8406–8407); S154 / Chapter 103 / `Estimating Probability Functions by Using the CONDDIST Statement` (PDF pp. 8407–8413).

## Scope

Implement Covariance-Correlation; Linear Test; Estimating Probability Functions by Using the CONDDIST. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Covariance-Correlation / Linear Test / Estimating Probability Functions by Using the CONDDIST, verify matrix dimensions, symmetry, parameter ordering, and boundaries; compare estimates or transformations for small analytically tractable matrices; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
