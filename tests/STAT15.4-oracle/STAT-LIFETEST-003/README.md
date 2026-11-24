# STAT-LIFETEST-003 — LIFETEST — TIME / Breslow, Fleming-Harrington, and Kaplan-Meier Methods / Life-Table Method

## Source

S154 / Chapter 77 / `TIME Statement` (PDF pp. 5669–5670); S154 / Chapter 77 / `Breslow, Fleming-Harrington, and Kaplan-Meier Methods` (PDF pp. 5671–5674); S154 / Chapter 77 / `Life-Table Method` (PDF pp. 5674–5676).

## Scope

Implement TIME; Breslow, Fleming-Harrington, and Kaplan-Meier Methods; Life-Table Method. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For TIME / Breslow, Fleming-Harrington, and Kaplan-Meier Methods / Life-Table Method, use a manually calculable event table to verify risk sets, survival estimates, variances, and intervals; include coincident events/censoring and entirely censored samples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 77.3: Life-Table Estimates for Males with Angina Pectoris; explicit statements: TIME |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: TIME. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
