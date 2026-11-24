# STAT-STDRATE-005 — STDRATE — Attributable Fraction and Population Attributable Fraction / Applicable Data Sets and Required Variables for Method Specifications

## Source

S154 / Chapter 116 / `Attributable Fraction and Population Attributable Fraction` (PDF pp. 9514–9518); S154 / Chapter 116 / `Applicable Data Sets and Required Variables for Method Specifications` (PDF pp. 9518–9519).

## Scope

Implement Attributable Fraction and Population Attributable Fraction; Applicable Data Sets and Required Variables for Method Specifications. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Attributable Fraction and Population Attributable Fraction / Applicable Data Sets and Required Variables for Method Specifications, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 116.3: Computing Attributable Fraction Estimates |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
