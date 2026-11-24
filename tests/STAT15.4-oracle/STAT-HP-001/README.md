# STAT-HP-001 — HP single-machine execution, data access, and format semantics

## Source

S154 / Chapter 21 / `Single-Machine Mode` (PDF pp. 555–556); S154 / Chapter 21 / `Single-Machine Data Access Mode` (PDF p. 556); S154 / Chapter 21 / `Output Data Sets` (PDF p. 556); S154 / Chapter 21 / `Working with Formats` (PDF pp. 556–557).

## Scope

Implement the documented single-machine execution and data access contracts; define supported data layouts, formats, and output semantics.

## Acceptance criteria

The same data must produce equivalent statistical results through supported access paths; formatted levels and output data sets must agree; unsupported execution modes cannot be treated as supported silently.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | HP CLASS/variable role integration, single-thread PERFORMANCE information |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
