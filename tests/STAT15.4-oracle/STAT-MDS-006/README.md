# STAT-MDS-006 — MDS — OUTFIT= Data Set / OUTRES= Data Set

## Source

S154 / Chapter 81 / `OUTFIT= Data Set` (PDF pp. 6398–6399); S154 / Chapter 81 / `OUTRES= Data Set` (PDF pp. 6399–6400).

## Scope

Implement OUTFIT= Data Set; OUTRES= Data Set. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For OUTFIT= Data Set / OUTRES= Data Set, verify triggering options, every variable name/type/format, row granularity, BY metadata, and numerical values; cover unrequested output, empty results, and multiple models; generate expected data sets independently of the implementation.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: MDS Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
