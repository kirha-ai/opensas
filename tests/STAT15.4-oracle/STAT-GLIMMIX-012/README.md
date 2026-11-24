# STAT-GLIMMIX-012 — GLIMMIX — Effects of Adding Overdispersion / Model or Integral Approximation / Notes on Bias of Estimators

## Source

S154 / Chapter 52 / `Effects of Adding Overdispersion` (PDF p. 3828); S154 / Chapter 52 / `Model or Integral Approximation` (PDF pp. 3828–3830); S154 / Chapter 52 / `Notes on Bias of Estimators` (PDF pp. 3843–3844).

## Scope

Implement Effects of Adding Overdispersion; Model or Integral Approximation; Notes on Bias of Estimators. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Effects of Adding Overdispersion / Model or Integral Approximation / Notes on Bias of Estimators, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 52.16: Diallel Experiment with Multimember Random Effects |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
