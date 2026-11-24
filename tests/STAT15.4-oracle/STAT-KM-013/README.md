# STAT-KM-013 — KM survival plot customization — Swapping Colors among Style Elements / Displaying a Style and Extracting Font Information / Displaying Other Style Elements

## Source

S154 / Chapter 26 / `Swapping Colors among Style Elements` (PDF pp. 1006–1008); S154 / Chapter 26 / `Displaying a Style and Extracting Font Information` (PDF pp. 1008–1010); S154 / Chapter 26 / `Displaying Other Style Elements` (PDF pp. 1010–1013).

## Scope

Implement swapping Colors among Style Elements; Displaying a Style and Extracting Font Information; Displaying Other Style Elements; change only the plot data, templates, macros, or style behavior specified by the source.

## Acceptance criteria

Reproduce the corresponding customization examples; survival estimates must remain consistent with the underlying model; verify censoring marks, numbers at risk, confidence bands, stratum order, and the specified template/style changes; visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Native Kaplan–Meier graph baseline and its template/ODS identity |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket. This is the native graph/template baseline; the specific customization named by this ticket still needs a focused follow-up case.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
