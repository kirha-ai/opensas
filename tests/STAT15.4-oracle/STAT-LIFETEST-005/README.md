# STAT-LIFETEST-005 — LIFETEST — Analysis of Competing-Risks Data

## Source

S154 / Chapter 77 / `Analysis of Competing-Risks Data` (PDF pp. 5687–5690).

## Scope

Implement Analysis of Competing-Risks Data. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Analysis of Competing-Risks Data, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: LIFETEST Procedure |
| [competing_risks.sas](competing_risks.sas) | captured | 0 | [listing](competing_risks.expected.txt) / [log](competing_risks.oracle.log) | Cumulative incidence with a censoring code, two failure causes, and two strata. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Restored the official treatment format from physical PDF page 5642.

**competing_risks:** Small explicit synthetic competing-risk input adapted from the official EVENTCODE example. It distinguishes a competing event from a censored observation.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
