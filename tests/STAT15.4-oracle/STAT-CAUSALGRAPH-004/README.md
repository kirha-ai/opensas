# STAT-CAUSALGRAPH-004 — CAUSALGRAPH — IDENTIFY / Statistical and Causal Concepts

## Source

S154 / Chapter 37 / `IDENTIFY Statement` (PDF pp. 2314–2316); S154 / Chapter 37 / `Statistical and Causal Concepts` (PDF p. 2322).

## Scope

Implement IDENTIFY; Statistical and Causal Concepts. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For IDENTIFY / Statistical and Causal Concepts, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: CAUSALGRAPH Procedure; explicit statements: IDENTIFY |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: IDENTIFY. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
