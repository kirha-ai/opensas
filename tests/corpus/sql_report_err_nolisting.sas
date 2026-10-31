/* BUG-sqlreportnotgated: a PROC SQL SELECT whose evaluation records a step
   error must print NO listing. The per-row eval path catches failures as
   Value.missing (a fabricated value) while the ERROR goes to the log — the
   old gate (NOEXEC/NOPRINT only) printed the fabricated table on stdout
   beside the stderr ERROR: a clean-looking listing for a step that failed,
   the worst failure class for clinical output. Oracle (real SAS 9.4,
   2026-10-31): this exact program prints NO listing (stdout empty), three
   ERROR lines in the log, and the step stops ("NOTE: The SAS System stopped
   processing this step because of errors."); SAS exits 2 by its own rc
   convention, opensas 1 per D-009 (user-program error). The clean SELECT
   first is the control — listings still print for a step with no errors.
   The erroring step is LAST because a step error skips every later step
   (BUG-errhalt). (no PHI; invented data)
   expect-rc: 1 */
data t;
  input g x;
  datalines;
1 3
1 2
0 2
0 1
;
run;

proc sql;
  select g, sum(x) as s from t group by g;  /* control: prints */
quit;

proc sql;
  select g, max(x) as mx
    from t
    group by g
    order by case when max(x)=3 then lag(x) else 0 end;  /* ERROR: no listing */
quit;
