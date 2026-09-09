data ev; input d; datalines;
5
15
25
;
run;
data rg; input lo hi band $; datalines;
0 10 low
10 20 mid
20 30 hi
;
run;
proc sql;
  select ev.d, rg.band from ev join rg on d>lo and d<=hi;
quit;
