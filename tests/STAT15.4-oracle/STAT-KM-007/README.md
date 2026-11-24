# STAT-KM-007 — KM survival plot customization — Changing the Second Title and Adding a Footnote / Adding a Custom Header above the At-Risk Table / Adding a Small Inset Table with Event Information / Adding an External Table with Event Information

## Source

S154 / Chapter 26 / `Changing the Second Title and Adding a Footnote` (PDF pp. 964–966); S154 / Chapter 26 / `Adding a Custom Header above the At-Risk Table` (PDF pp. 966–967); S154 / Chapter 26 / `Adding a Small Inset Table with Event Information` (PDF pp. 967–969); S154 / Chapter 26 / `Adding an External Table with Event Information` (PDF pp. 969–971).

## Scope

Implement changing the Second Title and Adding a Footnote; Adding a Custom Header above the At-Risk Table; Adding a Small Inset Table with Event Information; Adding an External Table with Event Information; change only the plot data, templates, macros, or style behavior specified by the source.

## Acceptance criteria

Reproduce the corresponding customization examples; survival estimates must remain consistent with the underlying model; verify censoring marks, numbers at risk, confidence bands, stratum order, and the specified template/style changes; visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Kaplan–Meier estimates with explicit at-risk table times |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket. This is the native graph/template baseline; the specific customization named by this ticket still needs a focused follow-up case.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
