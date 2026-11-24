# STAT-KM-005 — KM survival plot customization — Changing the Group Color / Changing the Line Pattern / Changing the Font / Changing the Legend and Inset Position

## Source

S154 / Chapter 26 / `Changing the Group Color` (PDF pp. 952–954); S154 / Chapter 26 / `Changing the Line Pattern` (PDF pp. 954–955); S154 / Chapter 26 / `Changing the Font` (PDF pp. 955–957); S154 / Chapter 26 / `Changing the Legend and Inset Position` (PDF pp. 957–958).

## Scope

Implement changing the Group Color; Changing the Line Pattern; Changing the Font; Changing the Legend and Inset Position; change only the plot data, templates, macros, or style behavior specified by the source.

## Acceptance criteria

Reproduce the corresponding customization examples; survival estimates must remain consistent with the underlying model; verify censoring marks, numbers at risk, confidence bands, stratum order, and the specified template/style changes; visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Native Kaplan–Meier graph baseline and its template/ODS identity |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket. This is the native graph/template baseline; the specific customization named by this ticket still needs a focused follow-up case.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
