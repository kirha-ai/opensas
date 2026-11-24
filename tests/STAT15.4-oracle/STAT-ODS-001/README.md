# STAT-ODS-001 — ODS — Output Defaults / Default Open Destination

## Source

S154 / Chapter 23 / `Output Defaults` (PDF pp. 580–583); S154 / Chapter 23 / `Default Open Destination` (PDF pp. 583–586).

## Scope

Implement output Defaults; Default Open Destination including object, selection, lifecycle, or presentation behavior; limit implementation to the cited functionality.

## Acceptance criteria

Build minimal programs from the corresponding ODS examples; verify object names/paths, selection/exclusion, output data sets, and cross-RUN state; inspect destination file contents rather than only checking file existence.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Real HTML destination creation versus LISTING behavior and observable destination content |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
