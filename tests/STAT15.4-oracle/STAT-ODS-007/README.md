# STAT-ODS-007 — ODS table metadata, TRACE, and OUTPUT data set contracts

## Source

S154 / Chapter 23 / `Paths and Selection` (PDF pp. 588–592); S154 / Chapter 23 / `Output Objects and ODS Destinations` (PDF pp. 586–587); S154 / Special SAS Data Sets / `Special SAS Data Sets` (PDF pp. 10879–10894).

## Scope

Standardize ODS table names, labels, paths, column descriptors, BY identifiers, and OUTPUT capture; procedure tickets define specific rows, columns, and triggering conditions.

## Acceptance criteria

TRACE must identify each object and OUTPUT must capture it by full/partial path; test same-named tables, multiple BY groups, SELECT/EXCLUDE, and empty tables; data sets preserve variable types, order, formats, and missing codes.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | ODS object paths, TRACE names and table selection |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
