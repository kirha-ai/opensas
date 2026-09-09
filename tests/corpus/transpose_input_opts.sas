data d;
  input g keepflag x y;
  datalines;
1 1 10 100
1 0 11 110
1 1 12 120
2 1 20 200
2 0 21 210
;
run;

/* where= dataset option: only keepflag=1 rows are transposed */
proc transpose data=d(where=(keepflag=1)) out=w1(drop=_name_);
  by g;
  var x;
run;
proc print data=w1 noobs; run;

/* keep= dataset option: only g and x survive, so only x is transposed */
proc transpose data=d(keep=g x) out=w2(drop=_name_);
  by g;
run;
proc print data=w2 noobs; run;

/* WHERE statement: same effect as the where= option above */
proc transpose data=d out=w3(drop=_name_);
  where keepflag=1;
  by g;
  var x;
run;
proc print data=w3 noobs; run;

/* plain TRANSPOSE, no input options: all rows transposed, unchanged */
proc transpose data=d out=w4(drop=_name_);
  by g;
  var x;
run;
proc print data=w4 noobs; run;
