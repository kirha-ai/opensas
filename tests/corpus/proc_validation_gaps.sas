/* GAP-tabprocopt + NOTE-sort0obsvalidation: two PROC-level validation gaps that
   used to be SILENT no-ops now fail loud (UNSUPPORTED/ERROR to stderr, exit 2).
   (1) an unknown PROC TABULATE proc option (`zonk`) used to be swallowed by the
       proc-option loop's catch-all — it now fails loud and renders NO table.
   (2) PROC SORT on a 0-observation input used to SKIP all BY validation; a bad
       BY variable now fails loud regardless of row count (SAS validates always).
   Positive controls run first (a valid TABULATE with a real proc option + a
   valid SORT still work); the fail-loud procs come LAST so they contribute
   nothing to stdout — if either silent-swallow regresses, a bogus table / a
   reordered print appears below and mismatches this fixture.
   expect-rc: 2 */
data d;
  input g $ x;
  datalines;
a 10
a 20
b 30
;
run;

/* positive: a valid TABULATE with a real proc option (format=) renders. */
proc tabulate data=d format=8.2; class g; var x; table g, x*sum; run;

/* positive: a valid SORT (any obs count) still sorts; PROC PRINT shows it. */
proc sort data=d out=srt; by descending x; run;
proc print data=srt; run;

/* empty0: a 0-observation dataset WITH a schema (columns g,x; no rows). */
data empty0; set d(obs=0); run;

/* (2) fail loud: a bad BY variable on a 0-obs input — used to be silently
   accepted because the 0-obs early return skipped validation. */
proc sort data=empty0 out=x; by nosuchvar; run;

/* (1) fail loud: an unknown TABULATE proc option `zonk` — used to be swallowed
   by the else-catch-all and the table rendered as if it weren't there. */
proc tabulate data=d zonk; class g; var x; table g, x*sum; run;
