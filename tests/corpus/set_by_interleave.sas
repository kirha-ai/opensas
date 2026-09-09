data a;
  input x;
  datalines;
1
3
5
;
run;
data b;
  input x;
  datalines;
2
4
6
;
run;
data c;
  set a b;
  by x;
run;
proc print data=c noobs; run;
