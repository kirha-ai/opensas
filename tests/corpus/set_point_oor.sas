/* NOTE-pointoorhard: an out-of-range POINT= read sets _ERROR_=1 and writes a
   NOTE, and the step CONTINUES — Statements Ref SET POINT= ("If SAS reads an
   invalid value of the POINT= variable, it sets the automatic variable
   _ERROR_ to 1") plus its CONTINUOUS-LOOP caution, which only makes sense if
   the step continues; Language Reference: Concepts p.488's `if _error_ then stop;` idiom is the user
   side of that contract. THIS FIXTURE DELIBERATELY INVERTS the e1d73fbf pin
   (BUG-pointnobs, "halt like the array-OOR paths"): the halt made the
   documented idiom unrunnable — rc 1, and the ERROR errhalt-poisoned the
   session so AFTER never printed. Now BEFORE and AFTER both print and rc is
   0. Unguarded (no `if _error_` check), the DO loop runs to its end: i=4/5
   each NOTE and their explicit OUTPUT writes the retained stale PDV (obs-3
   values) with _ERROR_=1 — the stale-PDV re-output is an oracle-blocked pick
   (SAS retention semantics), pinned as firmly in its NOTE class + _ERROR_=1
   by the captured-diagnostics test in src/exec.zig as the halt was before.
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
    output;
  end;
  stop;
run;
data _null_;
  put 'AFTER';
run;
