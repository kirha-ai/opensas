# STAT-POWER-015 — POWER — Analyses in the TWOSAMPLESURVIVAL / Analyses in the TWOSAMPLEWILCOXON

## Source

S154 / Chapter 96 / `Analyses in the TWOSAMPLESURVIVAL Statement` (PDF pp. 7912–7915); S154 / Chapter 96 / `Analyses in the TWOSAMPLEWILCOXON Statement` (PDF pp. 7915–7917).

## Scope

Implement Analyses in the TWOSAMPLESURVIVAL; Analyses in the TWOSAMPLEWILCOXON. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Analyses in the TWOSAMPLESURVIVAL / Analyses in the TWOSAMPLEWILCOXON, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 96.2: The Sawtooth Power Function in Proportion Analyses |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
