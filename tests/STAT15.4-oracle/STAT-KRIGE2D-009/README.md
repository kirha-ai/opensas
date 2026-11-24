# STAT-KRIGE2D-009 — KRIGE2D — Zonal Anisotropy / Anisotropic Nugget Effect / Introduction

## Source

S154 / Chapter 74 / `Zonal Anisotropy` (PDF pp. 5478–5482); S154 / Chapter 74 / `Anisotropic Nugget Effect` (PDF p. 5482); S154 / Chapter 74 / `Introduction` (PDF pp. 5482–5483).

## Scope

Implement Zonal Anisotropy; Anisotropic Nugget Effect; Introduction. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Zonal Anisotropy / Anisotropic Nugget Effect / Introduction, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 74.2: Investigating the Effect of Model Specification on Spatial Prediction |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
