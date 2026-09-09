/* GAP-univmissingtable, the CONFORMANT half — pinned green so the missing-count
   work cannot regress the number it has to agree with.

   Base SAS 9.4 Procedures Guide: Statistical Procedures, printed p.408
   (`=== pdf 411 ===`, offset +3), "Details: UNIVARIATE Procedure / Missing
   Values": "PROC UNIVARIATE excludes missing values for an analysis variable
   before calculating statistics."

   So UNIVARIATE's N is a NON-MISSING count, and when the "Missing Values"
   table is finally rendered its count must be the complement of this N against
   the observation total — not an independently computed number that can drift.
   This fixture pins the three quantities and their arithmetic on the same data:

     * UNIVARIATE Moments N = 4 (of 6 observations, 2 missing)
     * UNIVARIATE `output out= n= nmiss=` = 4 and 2 — the count ALREADY EXISTS
       and is already correct; only the DISPLAY table is missing
     * PROC MEANS N / N Miss = 4 / 2 — the same two numbers from the sibling
     * 4 + 2 = 6 = the row count from PROC FREQ's own missing line

   Also pins the INTERNAL INCONSISTENCY that makes this more than a missing
   line: PROC FREQ prints "Frequency Missing = 2" and PROC MEANS prints
   "N Miss 2" for this very data, while UNIVARIATE prints neither — one program,
   three PROCs, two of them reporting and one silent.

   Deliberately uses NO WEIGHT and NO FREQ statement: p.408's pre-exclusion
   rules make those cases contested (see docs/findings/univ-missingvalues-reading.md
   §4), and a fixture must not quietly enshrine a disputed reading.
   expect-rc: 0 */
data d;
  input x @@;
datalines;
1 2 . 4 . 6
;
run;

title "UNIVARIATE: Moments N must be 4, the NON-MISSING count";
proc univariate data=d;
  var x;
run;

title "UNIVARIATE already COMPUTES the count: n=4 nmiss=2 via OUTPUT";
proc univariate data=d noprint;
  var x;
  output out=uo n=n_ nmiss=nm_;
run;
proc print data=uo noobs;
run;

title "MEANS: the same two numbers from the sibling PROC";
proc means data=d n nmiss;
  var x;
run;

title "FREQ: prints Frequency Missing = 2 where UNIVARIATE prints nothing";
proc freq data=d;
  tables x;
run;
