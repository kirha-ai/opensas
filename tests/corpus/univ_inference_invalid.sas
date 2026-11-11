/* FEAT-univ-inference: CIBASIC TYPE= accepts LOWER/UPPER/TWOSIDED.
   SYMMETRIC belongs to CIPCTLDF, not CIBASIC. expect-rc: 1 */
data d;x=1;run;
proc univariate data=d cibasic(type=symmetric);var x;run;
