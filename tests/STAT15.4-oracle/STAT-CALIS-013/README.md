# STAT-CALIS-013 — CALIS — RAM / The RAM Model

## Source

S154 / Chapter 33 / `RAM Statement` (PDF pp. 1643–1649); S154 / Chapter 33 / `The RAM Model` (PDF pp. 1720–1728).

## Scope

Implement RAM; The RAM Model. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For RAM / The RAM Model, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 33.29: Fitting the RAM and EQS Models by the COSAN Modeling Language; explicit statements: RAM |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: RAM. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
