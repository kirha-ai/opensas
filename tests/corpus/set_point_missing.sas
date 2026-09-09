/* NOTE-pointoorhard: a MISSING POINT= obs number (p never assigned) is the
   same "invalid value of the POINT= variable" the Statements Ref describes —
   it sets _ERROR_=1 and writes a NOTE, and the step CONTINUES (its
   CONTINUOUS-LOOP caution only makes sense then; Language Reference: Concepts p.488's idiom is the
   user side). The explicit OUTPUT on the failing iteration writes the
   never-loaded all-missing PDV (SAS retention semantics, oracle-blocked pick
   — ponytail-marked at the .set arm), STOP ends the step, and BEFORE and
   AFTER both print at rc 0. Deliberately inverts the e1d73fbf pin
   (BUG-pointnobs halt): the NOTE text + _ERROR_=1 are pinned by the
   captured-diagnostics test in src/exec.zig.
   expect-rc: 0 */
data d; input x; datalines;
10
;
run;
data _null_;
  put 'BEFORE';
run;
data b;
  set d point=p;
  output;
  stop;
run;
data _null_;
  put 'AFTER';
run;
