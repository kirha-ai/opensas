# STAT-FACTOR-012 — FACTOR — Heywood Cases and Other Anomalies about Communality Estimates / Cautions

## Source

S154 / Chapter 44 / `Heywood Cases and Other Anomalies about Communality Estimates` (PDF pp. 2833–2834); S154 / Chapter 44 / `Cautions` (PDF p. 2835).

## Scope

Implement Heywood Cases and Other Anomalies about Communality Estimates; Cautions. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For Heywood Cases and Other Anomalies about Communality Estimates / Cautions, construct boundary or counterexamples for each explicit applicability restriction; verify diagnostics, termination status, and result availability; record specific needs-oracle questions for undocumented behavior rather than inventing successful behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Maximum-likelihood one- and two-factor fits with HEYWOOD |
| [improper_three_factor.sas](improper_three_factor.sas) | captured | 2 | [listing](improper_three_factor.expected.txt) / [log](improper_three_factor.oracle.log) | Deliberately excessive factor retention: warning and improper-optimum error |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. The documented improper three-factor fit is isolated as an explicit negative case.

**improper_three_factor:** Intentional negative case for the documented Heywood/overfactoring cautions. The positive one- and two-factor fits are separate.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
