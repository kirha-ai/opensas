# STAT-KM-002 — KM survival plot customization — Displaying the Patients-at-Risk Table inside the Plot / Displaying the Patients-at-Risk Table outside the Plot / Modifying At-Risk Table Times / Reordering the Groups

## Source

S154 / Chapter 26 / `Displaying the Patients-at-Risk Table inside the Plot` (PDF pp. 931–933); S154 / Chapter 26 / `Displaying the Patients-at-Risk Table outside the Plot` (PDF pp. 933–934); S154 / Chapter 26 / `Modifying At-Risk Table Times` (PDF pp. 934–937); S154 / Chapter 26 / `Reordering the Groups` (PDF pp. 937–939).

## Scope

Implement displaying the Patients-at-Risk Table inside the Plot; Displaying the Patients-at-Risk Table outside the Plot; Modifying At-Risk Table Times; Reordering the Groups; change only the plot data, templates, macros, or style behavior specified by the source.

## Acceptance criteria

Reproduce the corresponding customization examples; survival estimates must remain consistent with the underlying model; verify censoring marks, numbers at risk, confidence bands, stratum order, and the specified template/style changes; visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Kaplan–Meier estimates with explicit at-risk table times |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
