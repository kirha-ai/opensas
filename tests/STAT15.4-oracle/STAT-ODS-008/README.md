# STAT-ODS-008 — ODS destination compatibility scope and the D-022 migration design

## Source

S154 / Chapter 23 / `Output Objects and ODS Destinations` (PDF pp. 586–587); S154 / Chapter 23 / `The ODS Statement` (PDF pp. 587–588).

## Scope

Compare the guide's ODS destination semantics with the existing inert-destination policy in D-022 and define the SAS/STAT extension's design changes; deliver a design and migration plan that subsequent destination implementation follows.

## Acceptance criteria

Specify destination behaviors to retain, extend, or replace, observable diagnostics, and a regression migration plan; this backlog must not change D-022 runtime semantics before the design decision is settled.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Real HTML destination creation versus LISTING behavior and observable destination content |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
