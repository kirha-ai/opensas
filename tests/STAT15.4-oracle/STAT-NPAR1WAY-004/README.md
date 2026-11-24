# STAT-NPAR1WAY-004 — NPAR1WAY — Scores for Linear Rank and One-Way ANOVA Tests / Stratified Analysis / Hodges-Lehmann Estimation of Location Shift

## Source

S154 / Chapter 90 / `Scores for Linear Rank and One-Way ANOVA Tests` (PDF pp. 7239–7241); S154 / Chapter 90 / `Stratified Analysis` (PDF pp. 7241–7242); S154 / Chapter 90 / `Hodges-Lehmann Estimation of Location Shift` (PDF pp. 7242–7244).

## Scope

Implement Scores for Linear Rank and One-Way ANOVA Tests; Stratified Analysis; Hodges-Lehmann Estimation of Location Shift. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Scores for Linear Rank and One-Way ANOVA Tests / Stratified Analysis / Hodges-Lehmann Estimation of Location Shift, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 90.4: Hodges-Lehmann Estimation |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
