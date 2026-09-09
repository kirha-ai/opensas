data have;
  input name $ amt;
  datalines;
Alice 100
Bob 200
;
run;

proc print data=have noobs;
  sum amt;
run;
