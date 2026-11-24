# STAT-SURVEYSELECT-008 — SURVEYSELECT — Brewer’s PPS Method / Murthy’s PPS Method / Sampford’s PPS Method

## Source

S154 / Chapter 124 / `Brewer’s PPS Method` (PDF p. 10255); S154 / Chapter 124 / `Murthy’s PPS Method` (PDF pp. 10255–10256); S154 / Chapter 124 / `Sampford’s PPS Method` (PDF p. 10256).

## Scope

Implement Brewer’s PPS Method; Murthy’s PPS Method; Sampford’s PPS Method. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Brewer’s PPS Method / Murthy’s PPS Method / Sampford’s PPS Method, verify target distributions, units, design constraints, output identifiers, and fixed-seed reproducibility for sampling, randomization, or simulation; enumerate designs to validate inclusion probabilities/combinations, and check simulated distributions using analytic moments and Monte Carlo error bounds.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 124.3: PPS (Dollar-Unit) Sampling |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
