data master;
  input id x y;
  datalines;
1 10 100
2 20 200
3 30 300
;
run;
data trans;
  input id x y;
  datalines;
2 . 250
3 35 .
4 40 400
;
run;
data master2;
  update master trans;
  by id;
run;
proc print data=master2 noobs; run;
