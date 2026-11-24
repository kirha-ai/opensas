# STAT-BOXPLOT-003 — BOXPLOT — Percentile Definitions / Continuous Group Variables / Displaying Blocks of Data

## Source

S154 / Chapter 32 / `Percentile Definitions` (PDF pp. 1415–1416); S154 / Chapter 32 / `Continuous Group Variables` (PDF pp. 1416–1418); S154 / Chapter 32 / `Displaying Blocks of Data` (PDF pp. 1423–1425).

## Scope

Implement Percentile Definitions; Continuous Group Variables; Displaying Blocks of Data. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Percentile Definitions / Continuous Group Variables / Displaying Blocks of Data, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: BOXPLOT Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Prints native OUTBOX rows as the numerical companion to the rendered boxes; text still does not verify the plot image.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
