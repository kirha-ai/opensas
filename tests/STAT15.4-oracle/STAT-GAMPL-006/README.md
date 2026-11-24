# STAT-GAMPL-006 — GAMPL — Dispersion Parameter / First- or Second-Order Techniques / Technique Descriptions

## Source

S154 / Chapter 49 / `Dispersion Parameter` (PDF p. 3383); S154 / Chapter 49 / `First- or Second-Order Techniques` (PDF pp. 3385–3387); S154 / Chapter 49 / `Technique Descriptions` (PDF pp. 3387–3389).

## Scope

Implement Dispersion Parameter; First- or Second-Order Techniques; Technique Descriptions. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Dispersion Parameter / First- or Second-Order Techniques / Technique Descriptions, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: GAMPL Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
