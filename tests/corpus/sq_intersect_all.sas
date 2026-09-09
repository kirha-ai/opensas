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
  create table ia as select v from a intersect all select v from b;
quit;
proc print data=ia noobs; run;
