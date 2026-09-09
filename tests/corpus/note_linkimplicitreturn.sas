/* NOTE-linkimplicitreturn: a LINK-ed block that falls OFF THE END of the
   DATA step without an explicit RETURN is ended by the step's IMPLIED
   RETURN — "Every DATA step has an implied RETURN as its last executable
   statement" (Statements ref p.325) — and a RETURN after a LINK "returns
   execution to the statement that follows the LINK statement" (p.116
   comparisons, p.222 LINK Details; Language Reference: Concepts p.485 Table 20.3). Before the fix
   opensas silently DROPPED the pending LINK at the end of the op stream:
   the statements between the LINK and the subroutine never ran (y stayed
   missing) — a silent wrong answer. */

/* u1 (unsplit, INPUT-driven): sub falls off the end -> implied RETURN pops
   back to y=99, whose explicit RETURN then ends the iteration. y MUST be 99. */
data u1;
  input x;
  link sub;
  y = 99;
  return;
  sub: z = x * 2;
datalines;
1
2
;
run;
data _null_; set u1; put "u1 x=" x "y=" y "z=" z; run;

/* u2 (nested): tail falls off the end -> implied RETURN pops the INNER link
   (mid's tail runs, w=1), mid's explicit RETURN pops the outer (y=1). */
data u2;
  input x;
  link mid;
  y = 1;
  return;
  mid: link tail;
       w = 1;
       return;
  tail: z = x * 2;
datalines;
5
;
run;
data _null_; set u2; put "u2 x=" x "y=" y "z=" z "w=" w; run;

/* u3 (SET-driven split step): same rule with the read in the middle —
   sub falls off the end, implied RETURN pops back, y = v+1 runs. */
data d; input v; datalines;
10
20
;
run;
data u3;
  set d;
  link sub;
  y = v + 1;
  return;
  sub: z = v * 2;
run;
data _null_; set u3; put "u3 v=" v "y=" y "z=" z; run;

/* u4 (LINK issued BEFORE the driving SET — the BUG-linkacrossset family —
   whose block falls off the end): the implied RETURN pops back into the
   prefix, the read still executes exactly once, in order. */
data u4;
  link init;
  set d;
  x = v * mult;
  return;
  init: mult = 10;
run;
data _null_; set u4; put "u4 v=" v "x=" x "mult=" mult; run;

/* u5 (contrast): a GOTO — NOT a LINK — falling off the end returns to the
   TOP of the step (p.116: a RETURN after a GOTO goes to the beginning), so
   y=99 is skipped and y stays missing. Unchanged by the fix. */
data u5;
  input x;
  goto sub;
  y = 99;
  return;
  sub: z = x * 2;
datalines;
1
;
run;
data _null_; set u5; put "u5 x=" x "y=" y "z=" z; run;
