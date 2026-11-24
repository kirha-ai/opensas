# STAT-GRAPHICS-015 — ODS graphics — The SGPLOT Procedure / The SGSCATTER Procedure / The SGPANEL Procedure

## Source

S154 / Chapter 24 / `The SGPLOT Procedure` (PDF pp. 763–764); S154 / Chapter 24 / `The SGSCATTER Procedure` (PDF pp. 764–766); S154 / Chapter 24 / `The SGPANEL Procedure` (PDF pp. 766–768).

## Scope

Implement the SGPLOT Procedure; The SGSCATTER Procedure; The SGPANEL Procedure; define the scope and reset behavior of graph selection, files, templates, or styles.

## Acceptance criteria

Use the source examples to check graph object names, coordinates/data, legends/groups, styles, or file naming; exercise ON/OFF, repeated calls, and multiple destinations; inspect images visually when needed and validate statistics numerically as well.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | SGPLOT, SGSCATTER and SGPANEL object generation |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket. Text and SVG file-name evidence do not substitute for capturing and visually checking the image content.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
