# STAT-KM-012 — KM survival plot customization — Changing the Style / Color Priority Styles / Displaying a Style and Extracting Color Lists / Modifying Color Lists

## Source

S154 / Chapter 26 / `Changing the Style` (PDF pp. 1000–1001); S154 / Chapter 26 / `Color Priority Styles` (PDF pp. 1001–1002); S154 / Chapter 26 / `Displaying a Style and Extracting Color Lists` (PDF pp. 1002–1005); S154 / Chapter 26 / `Modifying Color Lists` (PDF pp. 1005–1006).

## Scope

Implement changing the Style; Color Priority Styles; Displaying a Style and Extracting Color Lists; Modifying Color Lists; change only the plot data, templates, macros, or style behavior specified by the source.

## Acceptance criteria

Reproduce the corresponding customization examples; survival estimates must remain consistent with the underlying model; verify censoring marks, numbers at risk, confidence bands, stratum order, and the specified template/style changes; visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Native Kaplan–Meier graph baseline and its template/ODS identity |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket. This is the native graph/template baseline; the specific customization named by this ticket still needs a focused follow-up case.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
