# STAT-DATASET-001 — Statistical data set types, matrices, and reserved metadata contracts

## Source

S154 / Special SAS Data Sets / `Introduction to Special SAS Data Sets` (PDF pp. 10880–10883).

## Scope

Represent statistical data set TYPE= attributes, matrix row identifiers, and reserved metadata consistently; subsequent type-specific tickets define the fields and formulas for each TYPE=.

## Acceptance criteria

Verify preservation of TYPE= attributes, reserved variable names/types, matrix row/column mappings, and incompatible-type diagnostics; do not guess or silently rewrite unknown data set types.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Native factor/correlation structure rows and descriptor |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket. Covers the named native output in this case; other TYPE= families grouped into the ticket need additional cases. Prints stable variable descriptors and data-set TYPE/NOBS/NVARS, excluding volatile creation timestamps and engine paths.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
