# STAT-SEQDESIGN-007 — SEQDESIGN — Error Spending Methods / Acceptance (beta) Boundary / Boundary Adjustments for Overlapping Lower and Upper beta Boundaries

## Source

S154 / Chapter 110 / `Error Spending Methods` (PDF pp. 8989–8991); S154 / Chapter 110 / `Acceptance (beta) Boundary` (PDF pp. 8991–8994); S154 / Chapter 110 / `Boundary Adjustments for Overlapping Lower and Upper beta Boundaries` (PDF pp. 8994–8995).

## Scope

Implement Error Spending Methods; Acceptance (beta) Boundary; Boundary Adjustments for Overlapping Lower and Upper beta Boundaries. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Error Spending Methods / Acceptance (beta) Boundary / Boundary Adjustments for Overlapping Lower and Upper beta Boundaries, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 110.10: Creating Two-Sided Error Spending Designs with and without Overlapping Lower and Upper beta Boundaries |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Keeps the complete adjusted/unadjusted beta-overlap designs; removes an incomplete trailing PROC header.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
