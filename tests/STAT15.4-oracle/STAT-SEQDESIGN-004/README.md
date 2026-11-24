# STAT-SEQDESIGN-004 — SEQDESIGN — One-Sided Fixed-Sample Tests in Clinical Trials / Two-Sided Fixed-Sample Tests in Clinical Trials / Group Sequential Methods

## Source

S154 / Chapter 110 / `One-Sided Fixed-Sample Tests in Clinical Trials` (PDF pp. 8963–8965); S154 / Chapter 110 / `Two-Sided Fixed-Sample Tests in Clinical Trials` (PDF pp. 8965–8968); S154 / Chapter 110 / `Group Sequential Methods` (PDF pp. 8968–8971).

## Scope

Implement One-Sided Fixed-Sample Tests in Clinical Trials; Two-Sided Fixed-Sample Tests in Clinical Trials; Group Sequential Methods. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For One-Sided Fixed-Sample Tests in Clinical Trials / Two-Sided Fixed-Sample Tests in Clinical Trials / Group Sequential Methods, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 110.8: Creating a One-Sided Error Spending Design |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
