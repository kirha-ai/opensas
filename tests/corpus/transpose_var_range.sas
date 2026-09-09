/* BUG-transposevarrange: `var v1-v5` must transpose all 5 vars (5 rows/group),
   not just the endpoints v1 and v5. */
data wide;
  input id v1 v2 v3 v4 v5;
  datalines;
1 10 20 30 40 50
2 11 21 31 41 51
;
run;
proc transpose data=wide out=long;
  by id;
  var v1-v5;
run;
proc print data=long noobs; run;
