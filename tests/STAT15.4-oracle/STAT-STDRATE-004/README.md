# STAT-STDRATE-004 — STDRATE — Direct Standardization / Mantel-Haenszel Effect Estimation / Indirect Standardization and Standardized Morbidity/Mortality Ratio

## Source

S154 / Chapter 116 / `Direct Standardization` (PDF pp. 9507–9509); S154 / Chapter 116 / `Mantel-Haenszel Effect Estimation` (PDF pp. 9509–9511); S154 / Chapter 116 / `Indirect Standardization and Standardized Morbidity/Mortality Ratio` (PDF pp. 9511–9514).

## Scope

Implement Direct Standardization; Mantel-Haenszel Effect Estimation; Indirect Standardization and Standardized Morbidity/Mortality Ratio. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Direct Standardization / Mantel-Haenszel Effect Estimation / Indirect Standardization and Standardized Morbidity/Mortality Ratio, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 116.2: Computing Mantel-Haenszel Risk Estimation |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
