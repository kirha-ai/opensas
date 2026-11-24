# STAT-MI-009 — MI — Parameter Simulation versus Multiple Imputation / Sensitivity Analysis for the MAR Assumption / Multiple Imputation with Pattern-Mixture Models

## Source

S154 / Chapter 82 / `Parameter Simulation versus Multiple Imputation` (PDF pp. 6483–6484); S154 / Chapter 82 / `Sensitivity Analysis for the MAR Assumption` (PDF pp. 6484–6485); S154 / Chapter 82 / `Multiple Imputation with Pattern-Mixture Models` (PDF pp. 6485–6486).

## Scope

Implement Parameter Simulation versus Multiple Imputation; Sensitivity Analysis for the MAR Assumption; Multiple Imputation with Pattern-Mixture Models. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Parameter Simulation versus Multiple Imputation / Sensitivity Analysis for the MAR Assumption / Multiple Imputation with Pattern-Mixture Models, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 82.14: Multistage Imputation |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
