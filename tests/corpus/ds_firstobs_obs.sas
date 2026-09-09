data a;
  input x;
  datalines;
10
20
30
40
;
run;
data b; set a(firstobs=2 obs=3); run;
proc print data=b noobs; run;
