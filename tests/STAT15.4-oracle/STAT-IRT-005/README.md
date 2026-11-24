# STAT-IRT-005 — IRT — FIXVALUE / GROUP / MEAN

## Source

S154 / Chapter 72 / `FIXVALUE Statement` (PDF pp. 5327–5332); S154 / Chapter 72 / `GROUP Statement` (PDF pp. 5332–5333); S154 / Chapter 72 / `MEAN Statement` (PDF pp. 5333–5334).

## Scope

Implement FIXVALUE; GROUP; MEAN. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For FIXVALUE / GROUP / MEAN, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: FIXVALUE, GROUP, MEAN.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
