# STAT-KM-006 — KM survival plot customization — Changing How the Censored Points Are Displayed / Adding a Y-Axis Reference Line / Adding Y-Axis Grid Lines / Changing the Homogeneity Test Inset

## Source

S154 / Chapter 26 / `Changing How the Censored Points Are Displayed` (PDF pp. 958–959); S154 / Chapter 26 / `Adding a Y-Axis Reference Line` (PDF pp. 959–961); S154 / Chapter 26 / `Adding Y-Axis Grid Lines` (PDF pp. 961–962); S154 / Chapter 26 / `Changing the Homogeneity Test Inset` (PDF pp. 962–964).

## Scope

Implement changing How the Censored Points Are Displayed; Adding a Y-Axis Reference Line; Adding Y-Axis Grid Lines; Changing the Homogeneity Test Inset; change only the plot data, templates, macros, or style behavior specified by the source.

## Acceptance criteria

Reproduce the corresponding customization examples; survival estimates must remain consistent with the underlying model; verify censoring marks, numbers at risk, confidence bands, stratum order, and the specified template/style changes; visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Native Kaplan–Meier graph baseline and its template/ODS identity |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
