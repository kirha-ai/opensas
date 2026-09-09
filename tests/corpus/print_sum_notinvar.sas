data have;
  input a b;
  datalines;
1 100
2 200
;
run;

proc print data=have noobs;
  var a;
  sum b;
run;
