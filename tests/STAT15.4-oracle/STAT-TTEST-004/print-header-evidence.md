# PRINT heading-only golden corrections

The original `bootstrap_seeded.sas` now matches every output token, including its
PRINT header, without editing the program or its reference expected output.
The general rule is documented in SAS's SUGI 24 paper, *An Everyday Guide to
Version 7 of the SAS System*, “Mixed case variable names”: capital letters supply
automatic heading break points when needed. The paper's `DepartDate`/`ReturnDate`
example with `MMDDYY8.` and the current SAS/STAT 15.4 bootstrap oracle independently
exercise this behavior.

Source: https://support.sas.com/resources/papers/proceedings/proceedings/sugi24/Training/p312-24.pdf

Only two existing local corpus goldens moved in the first full gate. This commit
contains those layout corrections separately from implementation. No statistical
expected values, input programs, or original oracle files changed.

- `tests/corpus/modify_by_p595.txt`: `ReceivedDate` has explicit `MMDDYY10.`.
  Its 12-character name wraps into `Received` and `Date` in a 10-column field.
  The expected layout was derived from the old golden by splitting that heading
  and removing two padding spaces before each date. All 13 observation rows were
  compared field-for-field with the prior golden, including every identifier,
  inventory quantity, price and date; all are unchanged.
- `tests/corpus/stat_results_ods_freq.txt`: `RowPercent` and `ColPercent` have
  `F6.2` formats in `src/stat/ods_freq.zig`. Their unbroken `Percent` word needs
  seven columns, so the names wrap as `Row`/`Percent` and `Col`/`Percent`. The
  header assertions now require both header rows. Every one of the nine existing
  numeric/data-row assertions remains byte-identical.

The focused PRINT test uses the documented date-name shape and asserts unchanged
numeric/date cells. It separately verifies that LABEL keeps explicit labels whole
and SPLIT keeps its existing explicit split behavior. Column-panel partitioning
and cell-rendering code are untouched.

The first gate exited 1 solely for these two stale heading expectations:
1701/1701 unit tests and 11/11 program fixtures passed; corpus was 2306/2308.
A fresh exact-SHA gate is required after these corrections; that failed run is
not counted as green.
