# STAT-GLIMMIX-014 — GLIMMIX — Processing by Subjects / Comparing the GLIMMIX and MIXED Procedures / Notes on Output Statistics

## Source

S154 / Chapter 52 / `Processing by Subjects` (PDF pp. 3862–3864); S154 / Chapter 52 / `Comparing the GLIMMIX and MIXED Procedures` (PDF pp. 3882–3884); S154 / Chapter 52 / `Notes on Output Statistics` (PDF pp. 3891–3893).

## Scope

Implement Processing by Subjects; Comparing the GLIMMIX and MIXED Procedures; Notes on Output Statistics. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Processing by Subjects / Comparing the GLIMMIX and MIXED Procedures / Notes on Output Statistics, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: GLIMMIX Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
