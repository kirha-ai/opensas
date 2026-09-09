data d;
  input x;
  datalines;
-7
-5
-2
0
3
5
8
;
run;
proc print data=d noobs;
  where x between -5 and 5;
run;
proc print data=d noobs;
  where x between 1 and 10;
run;
