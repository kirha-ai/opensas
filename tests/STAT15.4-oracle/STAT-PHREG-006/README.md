# STAT-PHREG-006 — PHREG — Analysis of Competing-Risks Data

## Source

S154 / Chapter 92 / `Analysis of Competing-Risks Data` (PDF pp. 7402–7409).

## Scope

Implement Analysis of Competing-Risks Data. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Analysis of Competing-Risks Data, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 92.15: Analysis of Competing-Risks Data |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Restored the official DiseaseGroup format from physical PDF page 7564.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
