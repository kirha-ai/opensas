# STAT-NLMIXED-008 — NLMIXED — Active Set Methods / Line-Search Methods / Covariance Matrix

## Source

S154 / Chapter 89 / `Active Set Methods` (PDF pp. 7153–7155); S154 / Chapter 89 / `Line-Search Methods` (PDF pp. 7155–7156); S154 / Chapter 89 / `Covariance Matrix` (PDF pp. 7160–7161).

## Scope

Implement Active Set Methods; Line-Search Methods; Covariance Matrix. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Active Set Methods / Line-Search Methods / Covariance Matrix, verify matrix dimensions, symmetry, parameter ordering, and boundaries; compare estimates or transformations for small analytically tractable matrices; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
