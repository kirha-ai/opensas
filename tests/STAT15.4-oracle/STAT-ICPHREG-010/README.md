# STAT-ICPHREG-010 — ICPHREG — OUTPUT / Input and Output Data Sets

## Source

S154 / Chapter 70 / `OUTPUT Statement` (PDF pp. 5227–5228); S154 / Chapter 70 / `Input and Output Data Sets` (PDF p. 5246).

## Scope

Implement OUTPUT; Input and Output Data Sets. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For OUTPUT / Input and Output Data Sets, verify triggering options, every variable name/type/format, row granularity, BY metadata, and numerical values; cover unrequested output, empty results, and multiple models; generate expected data sets independently of the implementation.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 70.2: Plotting Predicted Survival and Cumulative Hazard Functions; explicit statements: OUTPUT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: OUTPUT. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
