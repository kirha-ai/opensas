# STAT-NPAR1WAY-003 — NPAR1WAY — Tied Values / Simple Linear Rank Tests for Two-Sample Data / One-Way ANOVA Tests

## Source

S154 / Chapter 90 / `Tied Values` (PDF p. 7236); S154 / Chapter 90 / `Simple Linear Rank Tests for Two-Sample Data` (PDF pp. 7236–7238); S154 / Chapter 90 / `One-Way ANOVA Tests` (PDF pp. 7238–7239).

## Scope

Implement Tied Values; Simple Linear Rank Tests for Two-Sample Data; One-Way ANOVA Tests. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Tied Values / Simple Linear Rank Tests for Two-Sample Data / One-Way ANOVA Tests, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 90.3: Exact Wilcoxon Two-Sample Test |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
