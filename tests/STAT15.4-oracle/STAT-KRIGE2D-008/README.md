# STAT-KRIGE2D-008 — KRIGE2D — Nested Models / The Nugget Effect / Geometric Anisotropy

## Source

S154 / Chapter 74 / `Nested Models` (PDF pp. 5471–5473); S154 / Chapter 74 / `The Nugget Effect` (PDF pp. 5473–5474); S154 / Chapter 74 / `Geometric Anisotropy` (PDF pp. 5475–5478).

## Scope

Implement Nested Models; The Nugget Effect; Geometric Anisotropy. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Nested Models / The Nugget Effect / Geometric Anisotropy, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 74.2: Investigating the Effect of Model Specification on Spatial Prediction |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
