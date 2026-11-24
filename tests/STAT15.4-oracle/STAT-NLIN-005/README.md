# STAT-NLIN-005 — NLIN — Automatic Derivatives / Special Variables / Troubleshooting

## Source

S154 / Chapter 88 / `Automatic Derivatives` (PDF pp. 7014–7016); S154 / Chapter 88 / `Special Variables` (PDF pp. 7024–7026); S154 / Chapter 88 / `Troubleshooting` (PDF pp. 7026–7028).

## Scope

Implement Automatic Derivatives; Special Variables; Troubleshooting. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Automatic Derivatives / Special Variables / Troubleshooting, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: NLIN Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
