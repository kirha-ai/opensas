# STAT-REG-013 — REG — Testing for Heteroscedasticity / Testing for Lack of Fit / Autocorrelation in Time Series Data

## Source

S154 / Chapter 105 / `Testing for Heteroscedasticity` (PDF pp. 8642–8643); S154 / Chapter 105 / `Testing for Lack of Fit` (PDF pp. 8643–8644); S154 / Chapter 105 / `Autocorrelation in Time Series Data` (PDF pp. 8647–8648).

## Scope

Implement Testing for Heteroscedasticity; Testing for Lack of Fit; Autocorrelation in Time Series Data. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Testing for Heteroscedasticity / Testing for Lack of Fit / Autocorrelation in Time Series Data, verify matrix dimensions, symmetry, parameter ordering, and boundaries; compare estimates or transformations for small analytically tractable matrices; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: REG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
