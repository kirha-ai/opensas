# STAT-HPSPLIT-004 — HPSPLIT — RULES / Building a Decision Tree / Splitting Criteria

## Source

S154 / Chapter 68 / `RULES Statement` (PDF pp. 5096–5097); S154 / Chapter 68 / `Building a Decision Tree` (PDF pp. 5097–5100); S154 / Chapter 68 / `Splitting Criteria` (PDF pp. 5100–5103).

## Scope

Implement RULES; Building a Decision Tree; Splitting Criteria. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For RULES / Building a Decision Tree / Splitting Criteria, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 68.3: Creating a Regression Tree |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: RULES.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
