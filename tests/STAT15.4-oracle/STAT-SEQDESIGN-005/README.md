# STAT-SEQDESIGN-005 — SEQDESIGN — Statistical Assumptions for Group Sequential Designs / Boundary Scales / Boundary Variables

## Source

S154 / Chapter 110 / `Statistical Assumptions for Group Sequential Designs` (PDF pp. 8971–8973); S154 / Chapter 110 / `Boundary Scales` (PDF pp. 8973–8975); S154 / Chapter 110 / `Boundary Variables` (PDF pp. 8975–8978).

## Scope

Implement Statistical Assumptions for Group Sequential Designs; Boundary Scales; Boundary Variables. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Statistical Assumptions for Group Sequential Designs / Boundary Scales / Boundary Variables, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 110.4: Generating Graphics Display for Sequential Designs |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
