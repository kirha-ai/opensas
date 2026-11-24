# STAT-COMMON-006 — CLASS level formation and ordering

## Source

S154 / Chapter 20 / `Levelization of Classification Variables` (PDF pp. 411–413).

## Scope

Represent formatted levels, ordering methods, reference levels, and missing levels consistently; integrate procedure-specific ORDER=/REF= and related options in PROC tickets.

## Acceptance criteria

Verify level ordering and column mappings for character, numeric, formatted, missing, and multiple-BY-group data; changes in input order may have only the effects allowed by the documentation.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [class_order.sas](class_order.sas) | captured | 0 | [listing](class_order.expected.txt) / [log](class_order.oracle.log) | CLASS level order and effect column interpretation |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
