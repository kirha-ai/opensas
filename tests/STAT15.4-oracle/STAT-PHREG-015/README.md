# STAT-PHREG-015 — PHREG — ROC / Schemper-Henderson Predictive Measure / Concordance Statistics / Time-Dependent ROC Curves

## Source

S154 / Chapter 92 / `ROC Statement` (PDF p. 7388); S154 / Chapter 92 / `Schemper-Henderson Predictive Measure` (PDF pp. 7429–7430); S154 / Chapter 92 / `Concordance Statistics` (PDF pp. 7434–7437); S154 / Chapter 92 / `Time-Dependent ROC Curves` (PDF pp. 7437–7441).

## Scope

Implement ROC; Schemper-Henderson Predictive Measure; Concordance Statistics; Time-Dependent ROC Curves. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For ROC / Schemper-Henderson Predictive Measure / Concordance Statistics / Time-Dependent ROC Curves, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 92.7: Time-Dependent Repeated Measurements of a Covariate |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: ROC.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
