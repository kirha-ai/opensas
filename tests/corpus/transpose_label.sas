data wide;
  input id sbp dbp;
  label sbp = "Systolic BP";
  datalines;
1 120 80
2 130 85
;
run;
proc transpose data=wide out=long;
  by id;
  var sbp dbp;
run;
proc print data=long noobs; run;

data plain;
  input id x y;
  datalines;
1 10 20
2 30 40
;
run;
proc transpose data=plain out=plong;
  by id;
  var x y;
run;
proc print data=plong noobs; run;
