# STAT-STDRATE-003 — STDRATE — REFERENCE / Rate / Risk

## Source

S154 / Chapter 116 / `REFERENCE Statement` (PDF pp. 9499–9500); S154 / Chapter 116 / `Rate` (PDF pp. 9502–9505); S154 / Chapter 116 / `Risk` (PDF pp. 9505–9507).

## Scope

Implement REFERENCE; Rate; Risk. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For REFERENCE / Rate / Risk, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: STDRATE Procedure; explicit statements: REFERENCE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: REFERENCE. Remaining statement variants: . List input preserves the 85+ stratum label independently of PDF column padding.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
