# STAT-GRAPHICS-007 — ODS graphics — Image File Types / Scalable Vector Graphics / Naming Graphic Image Files

## Source

S154 / Chapter 24 / `Image File Types` (PDF pp. 695–696); S154 / Chapter 24 / `Scalable Vector Graphics` (PDF pp. 696–697); S154 / Chapter 24 / `Naming Graphic Image Files` (PDF pp. 697–699).

## Scope

Implement image File Types; Scalable Vector Graphics; Naming Graphic Image Files; define the scope and reset behavior of graph selection, files, templates, or styles.

## Acceptance criteria

Use the source examples to check graph object names, coordinates/data, legends/groups, styles, or file naming; exercise ON/OFF, repeated calls, and multiple destinations; inspect images visually when needed and validate statistics numerically as well.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | ODS graphics enablement, explicit SVG format/size, graph identity and generated image file names |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket. Text and SVG file-name evidence do not substitute for capturing and visually checking the image content.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
