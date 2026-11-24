# STAT-MI-003 — MI — EM / FCS / MNAR

## Source

S154 / Chapter 82 / `EM Statement` (PDF pp. 6430–6431); S154 / Chapter 82 / `FCS Statement` (PDF pp. 6431–6436); S154 / Chapter 82 / `MNAR Statement` (PDF pp. 6440–6443).

## Scope

Implement EM; FCS; MNAR. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For EM / FCS / MNAR, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 82.1: EM Algorithm for MLE; explicit statements: EM |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: EM. Remaining statement variants: FCS, MNAR.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
