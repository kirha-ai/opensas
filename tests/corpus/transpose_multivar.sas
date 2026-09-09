data wide;
  input id sbp dbp hr;
  datalines;
1 120 80 70
2 130 85 72
;
run;
proc transpose data=wide out=long;
  by id;
  var sbp dbp hr;
run;
proc print data=long noobs; run;
