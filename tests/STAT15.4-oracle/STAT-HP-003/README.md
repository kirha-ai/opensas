# STAT-HP-003 — Shared HP CLASS and variable role syntax

## Source

S154 / Chapter 22 / `CLASS Statement` (PDF pp. 560–564); S154 / Chapter 22 / `FREQ Statement` (PDF p. 564); S154 / Chapter 22 / `ID Statement` (PDF p. 564); S154 / Chapter 22 / `VAR Statement` (PDF p. 570); S154 / Chapter 22 / `WEIGHT Statement` (PDF p. 570).

## Scope

Implement shared HP syntax and options for classification variables, frequencies, weights, and identifiers; preserve documented differences from conventional procedures.

## Acceptance criteria

For each role, verify types, repeated declarations, formatted levels, and missing-value propagation; exercise the same shared semantics in at least two HP procedures.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | HP CLASS/variable role integration, single-thread PERFORMANCE information |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
