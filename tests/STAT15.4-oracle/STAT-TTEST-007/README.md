# STAT-TTEST-007 — TTEST — Two-Independent-Sample Design

## Source

S154 / Chapter 128 / `Two-Independent-Sample Design` (PDF pp. 10624–10629).

## Scope

Implement Two-Independent-Sample Design. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Two-Independent-Sample Design, separately verify the documented equal-variance and unequal-variance paths, degrees-of-freedom approximations, probabilities, and intervals; include very unequal sample sizes; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [two_sample_variance.sas](two_sample_variance.sas) | captured | 0 | [listing](two_sample_variance.expected.txt) / [log](two_sample_variance.oracle.log) | Pooled, Satterthwaite and Cochran two-sample paths and equality-of-variance output |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
