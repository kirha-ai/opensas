# STAT-KM-004 — KM survival plot customization — The Modularized Templates / Changing the Plot Title / Modifying the Y Axis / Changing the Line Thickness

## Source

S154 / Chapter 26 / `The Modularized Templates` (PDF pp. 946–948); S154 / Chapter 26 / `Changing the Plot Title` (PDF pp. 948–949); S154 / Chapter 26 / `Modifying the Y Axis` (PDF pp. 949–951); S154 / Chapter 26 / `Changing the Line Thickness` (PDF pp. 951–952).

## Scope

Implement the Modularized Templates; Changing the Plot Title; Modifying the Y Axis; Changing the Line Thickness; change only the plot data, templates, macros, or style behavior specified by the source.

## Acceptance criteria

Reproduce the corresponding customization examples; survival estimates must remain consistent with the underlying model; verify censoring marks, numbers at risk, confidence bands, stratum order, and the specified template/style changes; visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Native Kaplan–Meier graph baseline and its template/ODS identity |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket. This is the native graph/template baseline; the specific customization named by this ticket still needs a focused follow-up case.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
