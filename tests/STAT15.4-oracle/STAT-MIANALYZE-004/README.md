# STAT-MIANALYZE-004 — MIANALYZE — Multiple Imputation Efficiency / Multivariate Inferences / Examples of the Complete-Data Inferences

## Source

S154 / Chapter 83 / `Multiple Imputation Efficiency` (PDF pp. 6572–6573); S154 / Chapter 83 / `Multivariate Inferences` (PDF pp. 6573–6574); S154 / Chapter 83 / `Examples of the Complete-Data Inferences` (PDF pp. 6575–6576).

## Scope

Implement Multiple Imputation Efficiency; Multivariate Inferences; Examples of the Complete-Data Inferences. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Multiple Imputation Efficiency / Multivariate Inferences / Examples of the Complete-Data Inferences, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: MIANALYZE Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
