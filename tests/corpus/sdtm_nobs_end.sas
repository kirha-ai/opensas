/* Total count + last-record flag via NOBS= and END= */
data lb;
  input AVAL;
  datalines;
10
20
30
;
run;
data flagged;
  set lb nobs=total end=last;
  seq = _n_;
  lastfl = last;
  keep seq AVAL total lastfl;
run;
proc print data=flagged; run;
