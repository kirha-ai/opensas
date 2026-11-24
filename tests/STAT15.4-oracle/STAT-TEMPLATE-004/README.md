# STAT-TEMPLATE-004 — Graph templates — Reverting to the Default Templates / Graph Template Modification Macro

## Source

S154 / Chapter 25 / `Reverting to the Default Templates` (PDF pp. 842–843); S154 / Chapter 25 / `Graph Template Modification Macro` (PDF pp. 843–848).

## Scope

Implement reverting to the Default Templates; Graph Template Modification Macro; preserve template lookup, modification, persistence, and fallback behavior.

## Acceptance criteria

Run the same graphics program with default and user templates, checking search precedence and the expected visual differences; removing a user override must restore defaults; explicitly reject unknown templates and unsupported GTL constructs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Custom GTL template definition and rendering through SGRENDER |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket. Text and SVG file-name evidence do not substitute for capturing and visually checking the image content.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
