data master;
  input id x y;
  datalines;
1 10 100
2 20 200
;
run;
data trans;
  input id x y;
  datalines;
1 . 111
1 15 .
1 . 222
;
run;
data out;
  update master trans;
  by id;
run;
proc print data=out noobs; run;
