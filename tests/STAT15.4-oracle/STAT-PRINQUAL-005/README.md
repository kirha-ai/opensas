# STAT-PRINQUAL-005 — PRINQUAL — Using the MAC Method / Avoiding Constant Transformations / Constant Variables

## Source

S154 / Chapter 99 / `Using the MAC Method` (PDF pp. 8064–8065); S154 / Chapter 99 / `Avoiding Constant Transformations` (PDF p. 8068); S154 / Chapter 99 / `Constant Variables` (PDF p. 8068).

## Scope

Implement Using the MAC Method; Avoiding Constant Transformations; Constant Variables. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Using the MAC Method / Avoiding Constant Transformations / Constant Variables, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 99.1: Multidimensional Preference Analysis of Automobile Data |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Reconstructed Make/Model field padding so the 25 one-digit official ratings start in column 25.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
