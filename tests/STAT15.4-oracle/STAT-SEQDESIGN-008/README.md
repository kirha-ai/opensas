# STAT-SEQDESIGN-008 — SEQDESIGN — Specified and Derived Parameters / Applicable Boundary Keys / Sample Size Computation

## Source

S154 / Chapter 110 / `Specified and Derived Parameters` (PDF pp. 8995–8996); S154 / Chapter 110 / `Applicable Boundary Keys` (PDF pp. 8996–8997); S154 / Chapter 110 / `Sample Size Computation` (PDF pp. 8997–9005).

## Scope

Implement Specified and Derived Parameters; Applicable Boundary Keys; Sample Size Computation. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Specified and Derived Parameters / Applicable Boundary Keys / Sample Size Computation, verify forward power calculations, inverse solutions, rounding, and feasible boundaries; substituting the returned value into the original problem must meet the documented accuracy; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 110.14: Computing Sample Size for Survival Data That Have Uniform Accrual |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
