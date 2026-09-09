data scores;
  input v;
  datalines;
10
20
30
40
50
60
70
80
;
run;
proc univariate data=scores noprint;
  var v;
  output out=stats n=n mean=mean median=median std=std p25=q1 p75=q3 min=min max=max;
run;
proc print data=stats noobs; run;
