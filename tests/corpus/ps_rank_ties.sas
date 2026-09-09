data d;
  input id v;
  datalines;
1 10
2 20
3 20
4 30
;
run;
proc rank data=d out=r ties=mean;
  var v;
  ranks rnk;
run;
proc print data=r noobs; run;
