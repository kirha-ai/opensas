# STAT-SURVEYSELECT-010 — SURVEYSELECT — Specifying the Margin of Error

## Source

S154 / Chapter 124 / `Specifying the Margin of Error` (PDF pp. 10259–10260).

## Scope

Implement Specifying the Margin of Error. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Specifying the Margin of Error, verify target distributions, units, design constraints, output identifiers, and fixed-seed reproducibility for sampling, randomization, or simulation; enumerate designs to validate inclusion probabilities/combinations, and check simulated distributions using analytic moments and Monte Carlo error bounds.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
