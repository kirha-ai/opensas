# STAT-TREE-003 — TREE — HEIGHT / NAME / PARENT

## Source

S154 / Chapter 127 / `HEIGHT Statement` (PDF p. 10582); S154 / Chapter 127 / `NAME Statement` (PDF p. 10582); S154 / Chapter 127 / `PARENT Statement` (PDF pp. 10582–10583).

## Scope

Implement HEIGHT; NAME; PARENT. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For HEIGHT / NAME / PARENT, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: TREE Procedure; explicit statements: HEIGHT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: HEIGHT. Remaining statement variants: NAME, PARENT. Uses list input and underscore-separated country labels so protein measurements retain their fields. Traditional TREE graphics use a temporary SVG destination.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
