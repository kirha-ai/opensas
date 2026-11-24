# STAT-LOGISTIC-012 — LOGISTIC — ROC / ROCCONTRAST / Receiver Operating Characteristic Curves

## Source

S154 / Chapter 79 / `ROC Statement` (PDF pp. 5896–5897); S154 / Chapter 79 / `ROCCONTRAST Statement` (PDF pp. 5897–5898); S154 / Chapter 79 / `Receiver Operating Characteristic Curves` (PDF pp. 5934–5937).

## Scope

Implement ROC; ROCCONTRAST; Receiver Operating Characteristic Curves. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For ROC / ROCCONTRAST / Receiver Operating Characteristic Curves, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 79.8: Comparing Receiver Operating Characteristic Curves; explicit statements: ROC, ROCCONTRAST |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: ROC, ROCCONTRAST. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
