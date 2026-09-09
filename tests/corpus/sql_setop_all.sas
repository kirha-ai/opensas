data a;
  input x;
  datalines;
1
1
2
2
3
;
run;
data b;
  input x;
  datalines;
1
1
2
;
run;
proc sql;
  create table ea as select x from a except all select x from b;
  create table ia as select x from a intersect all select x from b;
quit;
proc print data=ea noobs; run;
proc print data=ia noobs; run;
