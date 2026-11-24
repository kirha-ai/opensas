# STAT-CALIS-016 — CALIS — STRUCTEQ / Standardized Solutions / Measures of Multivariate Kurtosis

## Source

S154 / Chapter 33 / `STRUCTEQ Statement` (PDF p. 1653); S154 / Chapter 33 / `Standardized Solutions` (PDF pp. 1799–1800); S154 / Chapter 33 / `Measures of Multivariate Kurtosis` (PDF pp. 1803–1805).

## Scope

Implement STRUCTEQ; Standardized Solutions; Measures of Multivariate Kurtosis. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For STRUCTEQ / Standardized Solutions / Measures of Multivariate Kurtosis, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 33.7: Multivariate Regression Models |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: STRUCTEQ.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
