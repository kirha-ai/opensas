# STAT-HPSPLIT-006 — HPSPLIT — Primary and Surrogate Splitting Rules / Unknown Values of Categorical Predictors / Variable Importance

## Source

S154 / Chapter 68 / `Primary and Surrogate Splitting Rules` (PDF pp. 5108–5109); S154 / Chapter 68 / `Unknown Values of Categorical Predictors` (PDF p. 5110); S154 / Chapter 68 / `Variable Importance` (PDF pp. 5115–5116).

## Scope

Implement Primary and Surrogate Splitting Rules; Unknown Values of Categorical Predictors; Variable Importance. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Primary and Surrogate Splitting Rules / Unknown Values of Categorical Predictors / Variable Importance, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 68.5: Assessing Variable Importance |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. Restored complete Dopant and Usable labels with list input after PDF column-space loss.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
