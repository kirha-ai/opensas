# STAT-SEQTEST-005 — SEQTEST — Analysis after a Sequential Test / Available Sample Space Orderings in a Sequential Test / Applicable Tests and Sample Size Computation

## Source

S154 / Chapter 111 / `Analysis after a Sequential Test` (PDF pp. 9180–9181); S154 / Chapter 111 / `Available Sample Space Orderings in a Sequential Test` (PDF pp. 9181–9183); S154 / Chapter 111 / `Applicable Tests and Sample Size Computation` (PDF pp. 9183–9184).

## Scope

Implement Analysis after a Sequential Test; Available Sample Space Orderings in a Sequential Test; Applicable Tests and Sample Size Computation. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Analysis after a Sequential Test / Available Sample Space Orderings in a Sequential Test / Applicable Tests and Sample Size Computation, verify forward power calculations, inverse solutions, rounding, and feasible boundaries; substituting the returned value into the original problem must meet the documented accuracy; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
