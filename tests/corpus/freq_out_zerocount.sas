/* BUG-freqoutzerocount (doc-finder tick276, F2): without ZEROS, OUT= omits a
   level seen only on zero-weight obs (B) — SAS emits no COUNT=0 row, so the
   OUT= has 2 obs (A, C). With `weight w / zeros` B is re-included at COUNT=0
   (3 obs). Non-zero levels keep their COUNT/PERCENT. */
data d; input x $ w @@; datalines;
A 1  A 2  B 0  C 5
;
run;
proc freq data=d; tables x / out=o1 noprint; weight w; run;
proc print data=o1; run;
proc freq data=d; tables x / out=o2 noprint; weight w / zeros; run;
proc print data=o2; run;
