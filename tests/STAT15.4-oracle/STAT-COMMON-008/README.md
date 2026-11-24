# STAT-COMMON-008 — Alternative parameterizations and reference coding

## Source

S154 / Chapter 20 / `Other Parameterizations` (PDF pp. 418–421).

## Scope

Implement the non-GLM parameterizations and reference-level semantics described in this section; expose them only to PROCs that document support for them.

## Acceptance criteria

Verify equivalent predictions before and after parameter transformations for the same fitted space; check each documented coding scheme rather than substituting a single scheme for all parameterizations.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [reference_effect_coding.sas](reference_effect_coding.sas) | captured | 0 | [listing](reference_effect_coding.expected.txt) / [log](reference_effect_coding.oracle.log) | Reference versus effect coding with an explicit response event |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
