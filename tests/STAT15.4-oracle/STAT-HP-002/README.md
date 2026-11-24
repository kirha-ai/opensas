# STAT-HP-002 — PERFORMANCE options and execution statistics

## Source

S154 / Chapter 21 / `PERFORMANCE Statement` (PDF pp. 557–558).

## Scope

Integrate PERFORMANCE statements, thread/execution settings, and performance information; report requested modes that the current environment cannot support.

## Acceptance criteria

Verify default and explicit settings, thread-count changes, invalid settings, and execution information; parallel-result differences must follow the algorithm's numerical-error and random-number policies.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | HP CLASS/variable role integration, single-thread PERFORMANCE information |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
