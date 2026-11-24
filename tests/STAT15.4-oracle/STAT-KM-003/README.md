# STAT-KM-003 — KM survival plot customization — Suppressing the Censored Observations / Failure Plots

## Source

S154 / Chapter 26 / `Suppressing the Censored Observations` (PDF pp. 939–940); S154 / Chapter 26 / `Failure Plots` (PDF pp. 940–946).

## Scope

Implement suppressing the Censored Observations; Failure Plots; change only the plot data, templates, macros, or style behavior specified by the source.

## Acceptance criteria

Reproduce the corresponding customization examples; survival estimates must remain consistent with the underlying model; verify censoring marks, numbers at risk, confidence bands, stratum order, and the specified template/style changes; visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Failure rather than survivor function plotting |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
