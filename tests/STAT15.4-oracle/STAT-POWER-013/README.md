# STAT-POWER-013 — POWER — Analyses in the ONESAMPLEMEANS / Analyses in the ONEWAYANOVA / Analyses in the PAIREDFREQ

## Source

S154 / Chapter 96 / `Analyses in the ONESAMPLEMEANS Statement` (PDF pp. 7887–7890); S154 / Chapter 96 / `Analyses in the ONEWAYANOVA Statement` (PDF pp. 7890–7892); S154 / Chapter 96 / `Analyses in the PAIREDFREQ Statement` (PDF pp. 7892–7895).

## Scope

Implement Analyses in the ONESAMPLEMEANS; Analyses in the ONEWAYANOVA; Analyses in the PAIREDFREQ. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Analyses in the ONESAMPLEMEANS / Analyses in the ONEWAYANOVA / Analyses in the PAIREDFREQ, verify paired differences, pairwise missing-value exclusion rules, degrees of freedom, and intervals; reversing pair order must correctly change direction and one-sided probabilities; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 96.2: The Sawtooth Power Function in Proportion Analyses |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
