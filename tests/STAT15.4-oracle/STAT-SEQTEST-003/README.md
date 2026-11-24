# STAT-SEQTEST-003 — SEQTEST — Boundary Variables / Information Level Adjustments at Future Stages / Boundary Adjustments for Information Levels

## Source

S154 / Chapter 111 / `Boundary Variables` (PDF pp. 9169–9172); S154 / Chapter 111 / `Information Level Adjustments at Future Stages` (PDF pp. 9172–9173); S154 / Chapter 111 / `Boundary Adjustments for Information Levels` (PDF pp. 9173–9175).

## Scope

Implement Boundary Variables; Information Level Adjustments at Future Stages; Boundary Adjustments for Information Levels. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Boundary Variables / Information Level Adjustments at Future Stages / Boundary Adjustments for Information Levels, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
