# STAT-POWER-010 — POWER — Sample Size Adjustment Options / Memory / CPU Time

## Source

S154 / Chapter 96 / `Sample Size Adjustment Options` (PDF p. 7853); S154 / Chapter 96 / `Memory` (PDF p. 7856); S154 / Chapter 96 / `CPU Time` (PDF pp. 7856–7857).

## Scope

Implement Sample Size Adjustment Options; Memory; CPU Time. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Sample Size Adjustment Options / Memory / CPU Time, verify forward power calculations, inverse solutions, rounding, and feasible boundaries; substituting the returned value into the original problem must meet the documented accuracy; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: POWER Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
