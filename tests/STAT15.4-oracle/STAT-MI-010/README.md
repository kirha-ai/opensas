# STAT-MI-010 — MI — Specifying Sets of Observations for Imputation in Pattern-Mixture Models / Adjusting Imputed Values in Pattern-Mixture Models / Summary of Issues in Multiple Imputation

## Source

S154 / Chapter 82 / `Specifying Sets of Observations for Imputation in Pattern-Mixture Models` (PDF pp. 6486–6487); S154 / Chapter 82 / `Adjusting Imputed Values in Pattern-Mixture Models` (PDF pp. 6487–6491); S154 / Chapter 82 / `Summary of Issues in Multiple Imputation` (PDF pp. 6491–6493).

## Scope

Implement Specifying Sets of Observations for Imputation in Pattern-Mixture Models; Adjusting Imputed Values in Pattern-Mixture Models; Summary of Issues in Multiple Imputation. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Specifying Sets of Observations for Imputation in Pattern-Mixture Models / Adjusting Imputed Values in Pattern-Mixture Models / Summary of Issues in Multiple Imputation, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 82.14: Multistage Imputation |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
