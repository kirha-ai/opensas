# STAT-MI-006 — MI — Monotone and FCS Predictive Mean Matching Methods / Monotone and FCS Discriminant Function Methods / Monotone and FCS Logistic Regression Methods

## Source

S154 / Chapter 82 / `Monotone and FCS Predictive Mean Matching Methods` (PDF pp. 6457–6458); S154 / Chapter 82 / `Monotone and FCS Discriminant Function Methods` (PDF pp. 6458–6460); S154 / Chapter 82 / `Monotone and FCS Logistic Regression Methods` (PDF pp. 6460–6463).

## Scope

Implement Monotone and FCS Predictive Mean Matching Methods; Monotone and FCS Discriminant Function Methods; Monotone and FCS Logistic Regression Methods. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Monotone and FCS Predictive Mean Matching Methods / Monotone and FCS Discriminant Function Methods / Monotone and FCS Logistic Regression Methods, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 82.4: Monotone Logistic Regression Method for CLASS Variables |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
