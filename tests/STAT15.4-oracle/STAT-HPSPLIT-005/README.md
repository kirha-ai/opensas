# STAT-HPSPLIT-005 — HPSPLIT — Splitting Strategy / Pruning / Memory Considerations

## Source

S154 / Chapter 68 / `Splitting Strategy` (PDF p. 5103); S154 / Chapter 68 / `Pruning` (PDF pp. 5103–5108); S154 / Chapter 68 / `Memory Considerations` (PDF p. 5108).

## Scope

Implement Splitting Strategy; Pruning; Memory Considerations. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Splitting Strategy / Pruning / Memory Considerations, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
