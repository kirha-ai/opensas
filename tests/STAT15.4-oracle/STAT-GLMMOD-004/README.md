# STAT-GLMMOD-004 — GLMMOD — OUTPARM= Data Set / OUTDESIGN= Data Set

## Source

S154 / Chapter 54 / `OUTPARM= Data Set` (PDF pp. 4240–4241); S154 / Chapter 54 / `OUTDESIGN= Data Set` (PDF p. 4241).

## Scope

Implement OUTPARM= Data Set; OUTDESIGN= Data Set. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For OUTPARM= Data Set / OUTDESIGN= Data Set, verify triggering options, every variable name/type/format, row granularity, BY metadata, and numerical values; cover unrequested output, empty results, and multiple models; generate expected data sets independently of the implementation.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: GLMMOD Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
