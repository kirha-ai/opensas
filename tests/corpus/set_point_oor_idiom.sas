/* NOTE-pointoorhard (manager tick356): CONFIRMED DEVIATION, now FIXED. In
   real SAS an out-of-range POINT= sets `_ERROR_=1` and writes a NOTE, and the
   step continues to the user's `if _error_ then stop;` — the whole POINT of
   the documented idiom (Statements Ref SET POINT=: "If SAS reads an invalid
   value of the POINT= variable, it sets the automatic variable _ERROR_ to 1";
   its CONTINUOUS-LOOP caution can only exist if the step continues; Language Reference: Concepts
   p.488 prints the idiom). opensas used to hard-halt (errhalt): the ERROR
   poisoned the session, rc=1, and PROC PRINT never ran. THIS FIXTURE'S GOLDEN
   IS THE SEMANTIC FLIP, pinned as firmly as the halt was: with the guard
   present, the failed i=4 read sets _ERROR_=1, the guard's STOP ends the
   step, and b holds exactly the 3 real rows (no stale re-output) — BEFORE and
   AFTER print and PROC PRINT RUNS. Three residuals stay oracle-blocked
   (NOTE-vs-ERROR class — NOTE chosen; SYSERR/rc — 0 chosen; stale-PDV
   re-output on an unguarded failing iteration — allowed, SAS retention) and
   are ponytail-marked at the .set arm in src/exec.zig.
   expect-rc: 0 */
data d; input x; datalines;
10
20
30
;
run;
data _null_;
  put 'BEFORE';
run;
data b;
  do i = 1 to 5;
    set d point=i;
    if _error_ then stop;
    output;
  end;
  stop;
run;
data _null_;
  put 'AFTER';
run;
proc print data=b; run;
