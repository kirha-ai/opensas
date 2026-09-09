data a; input v; datalines;
1
1
2
2
3
;
run;
data b; input v; datalines;
1
1
2
;
run;
proc sql;
  create table ea as select v from a except all select v from b;
quit;
proc print data=ea noobs; run;
