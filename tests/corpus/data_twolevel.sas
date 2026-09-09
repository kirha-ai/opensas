data src; input a b; datalines;
1 2
3 4
;
run;
/* DSOPT-out: a two-level libref.member output name must parse and produce a
   dataset (was: ERROR "DATA step options are not supported"). */
data tokeep.tokdm;
  set src;
  c = a + b;
run;
data back;
  set tokeep.tokdm;
run;
proc print data=back noobs; run;
