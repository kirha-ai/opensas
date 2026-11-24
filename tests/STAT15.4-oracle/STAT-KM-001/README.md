# STAT-KM-001 — KM survival plot customization — Enabling ODS Graphics and the Default Kaplan-Meier Plot / Individual Survival Plots / Hall-Wellner Confidence Bands and Homogeneity Test / Equal-Precision Bands

## Source

S154 / Chapter 26 / `Enabling ODS Graphics and the Default Kaplan-Meier Plot` (PDF pp. 925–927); S154 / Chapter 26 / `Individual Survival Plots` (PDF pp. 927–928); S154 / Chapter 26 / `Hall-Wellner Confidence Bands and Homogeneity Test` (PDF pp. 928–929); S154 / Chapter 26 / `Equal-Precision Bands` (PDF pp. 929–931).

## Scope

Implement enabling ODS Graphics and the Default Kaplan-Meier Plot; Individual Survival Plots; Hall-Wellner Confidence Bands and Homogeneity Test; Equal-Precision Bands; change only the plot data, templates, macros, or style behavior specified by the source.

## Acceptance criteria

Reproduce the corresponding customization examples; survival estimates must remain consistent with the underlying model; verify censoring marks, numbers at risk, confidence bands, stratum order, and the specified template/style changes; visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Kaplan–Meier Hall–Wellner confidence bands and homogeneity test request |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
