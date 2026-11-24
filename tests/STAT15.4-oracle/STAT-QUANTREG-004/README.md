# STAT-QUANTREG-004 — QUANTREG — CONDDIST / Quantile Regression as an Optimization Problem / Optimization Algorithms

## Source

S154 / Chapter 103 / `CONDDIST Statement` (PDF pp. 8379–8384); S154 / Chapter 103 / `Quantile Regression as an Optimization Problem` (PDF pp. 8393–8394); S154 / Chapter 103 / `Optimization Algorithms` (PDF pp. 8394–8402).

## Scope

Implement CONDDIST; Quantile Regression as an Optimization Problem; Optimization Algorithms. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For CONDDIST / Quantile Regression as an Optimization Problem / Optimization Algorithms, verify the requested quantiles, objective function, tie-breaking rules, and inference; cover extreme quantiles and rank-deficient designs; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 103.3: Quantile Regression Analysis of Birth-Weight Data |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: CONDDIST. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
