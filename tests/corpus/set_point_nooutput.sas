/* BUG-pointautooutput: with POINT= the DATA step performs NO implicit
   bottom-of-iteration OUTPUT — only an explicit OUTPUT statement writes a row
   (the same Language Reference: Concepts p.488 direct-access rule that forces the explicit STOP).
   Before the fix the implicit output fabricated a plausible 1-row dataset out
   of a STOP-less program. Both steps are STOP-less, so each ends via the
   no-progress guard (BUG-pointnoiterate): iteration 2 re-reads the same obs,
   which stops the step like STOP — where SAS itself would loop forever. */
data d; input v; datalines;
10
20
30
;
run;

/* no OUTPUT statement: ZERO rows — nothing is ever written */
data b; p=3; set d point=p; run;
proc print data=b noobs; run;

/* explicit OUTPUT: exactly ONE row — iteration 2's repeat read stops the step
   before it can write a second copy of obs 3 */
data c; p=3; set d point=p; output; run;
proc print data=c noobs; run;
