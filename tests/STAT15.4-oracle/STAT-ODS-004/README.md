# STAT-ODS-004 — ODS — The SAS Results Window / The ODS PATH Statement

## Source

S154 / Chapter 23 / `The SAS Results Window` (PDF pp. 592–594); S154 / Chapter 23 / `The ODS PATH Statement` (PDF p. 594).

## Scope

Implement the SAS Results Window; The ODS PATH Statement including object, selection, lifecycle, or presentation behavior; limit implementation to the cited functionality.

## Acceptance criteria

Build minimal programs from the corresponding ODS examples; verify object names/paths, selection/exclusion, output data sets, and cross-RUN state; inspect destination file contents rather than only checking file existence.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | ODS object paths, TRACE names and table selection |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
