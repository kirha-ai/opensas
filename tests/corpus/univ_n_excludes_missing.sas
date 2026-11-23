/* The SAS 9.4 Missing Values count complements the nonmissing N.
   The listing and OUTPUT OUT= show the same denominator for this
   unweighted variable. Statistical Procedures, printed p.408. */
data d;
  input x @@;
datalines;
1 2 . 4 . 6
;
run;

title "UNIVARIATE: Moments N must be 4, the NON-MISSING count";
proc univariate data=d;
  var x;
run;

title "UNIVARIATE already COMPUTES the count: n=4 nmiss=2 via OUTPUT";
proc univariate data=d noprint;
  var x;
  output out=uo n=n_ nmiss=nm_;
run;
proc print data=uo noobs;
run;

title "MEANS: the same two numbers from the sibling PROC";
proc means data=d n nmiss;
  var x;
run;

title "FREQ: prints Frequency Missing = 2 where UNIVARIATE prints nothing";
proc freq data=d;
  tables x;
run;
