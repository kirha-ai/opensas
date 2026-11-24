# STAT-GLM-006 — GLM — Effect Size Measures for F Tests in GLM / Absorption / Specification of ESTIMATE Expressions

## Source

S154 / Chapter 53 / `Effect Size Measures for F Tests in GLM` (PDF pp. 4120–4124); S154 / Chapter 53 / `Absorption` (PDF pp. 4124–4127); S154 / Chapter 53 / `Specification of ESTIMATE Expressions` (PDF pp. 4127–4128).

## Scope

Implement Effect Size Measures for F Tests in GLM; Absorption; Specification of ESTIMATE Expressions. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Effect Size Measures for F Tests in GLM / Absorption / Specification of ESTIMATE Expressions, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: GLM Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
