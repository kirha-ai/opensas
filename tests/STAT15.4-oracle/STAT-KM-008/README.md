# STAT-KM-008 — KM survival plot customization — Suppressing the Legend / Kaplan-Meier Plot with Event Table and Other Customizations / Displaying Percentages on the Y Axis / Compiled Template Cleanup

## Source

S154 / Chapter 26 / `Suppressing the Legend` (PDF pp. 971–972); S154 / Chapter 26 / `Kaplan-Meier Plot with Event Table and Other Customizations` (PDF pp. 972–973); S154 / Chapter 26 / `Displaying Percentages on the Y Axis` (PDF pp. 973–976); S154 / Chapter 26 / `Compiled Template Cleanup` (PDF p. 976).

## Scope

Implement suppressing the Legend; Kaplan-Meier Plot with Event Table and Other Customizations; Displaying Percentages on the Y Axis; Compiled Template Cleanup; change only the plot data, templates, macros, or style behavior specified by the source.

## Acceptance criteria

Reproduce the corresponding customization examples; survival estimates must remain consistent with the underlying model; verify censoring marks, numbers at risk, confidence bands, stratum order, and the specified template/style changes; visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Native Kaplan–Meier graph baseline and its template/ODS identity |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket. This is the native graph/template baseline; the specific customization named by this ticket still needs a focused follow-up case.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
