/* BUG-univclass (doc-finder tick136, HIGH silent-wrong): PROC UNIVARIATE CLASS was
   swallowed by the sub-statement loop's `else i+=1` — stats came out POOLED over all
   obs (here mean=8.5 n=4) and the CLASS var was dropped from OUT=. SAS 9.4 computes
   per-level: a→(mean 2, n 2), b→(mean 15, n 2), with g retained in OUT=. */
data d;
  input g $ x;
  datalines;
a 1
a 3
b 10
b 20
;
run;

proc univariate data=d;
  class g;
  var x;
  output out=s mean=m n=n;
run;

proc print data=s;
run;
