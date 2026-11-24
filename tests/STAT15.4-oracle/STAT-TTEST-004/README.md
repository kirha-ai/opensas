# STAT-TTEST-004 — TTEST — BOOTSTRAP / Bootstrap Methods

## Source

S154 / Chapter 128 / `BOOTSTRAP Statement` (PDF pp. 10613–10615); S154 / Chapter 128 / `Bootstrap Methods` (PDF pp. 10631–10640).

## Scope

Implement BOOTSTRAP; Bootstrap Methods. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For BOOTSTRAP / Bootstrap Methods, verify resampling units, replicate counts, fixed-seed reproducibility, successful replicate counts, and failed-replicate handling; validate intervals/probabilities against enumerated or error-bounded references.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [bootstrap_seeded.sas](bootstrap_seeded.sas) | captured | 0 | [listing](bootstrap_seeded.expected.txt) / [log](bootstrap_seeded.oracle.log) | Bootstrap sampling, fixed seed, percentile intervals and BOOTDATA layout |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
