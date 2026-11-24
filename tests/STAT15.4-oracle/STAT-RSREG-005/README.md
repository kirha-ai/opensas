# STAT-RSREG-005 — RSREG — Searching for Multiple Response Conditions / Handling Covariates / Computational Method

## Source

S154 / Chapter 108 / `Searching for Multiple Response Conditions` (PDF pp. 8882–8884); S154 / Chapter 108 / `Handling Covariates` (PDF pp. 8884–8885); S154 / Chapter 108 / `Computational Method` (PDF pp. 8885–8886).

## Scope

Implement Searching for Multiple Response Conditions; Handling Covariates; Computational Method. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Searching for Multiple Response Conditions / Handling Covariates / Computational Method, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 108.2: Response Surface Analysis with Covariates |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
