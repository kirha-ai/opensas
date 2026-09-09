data d;
  input name $ age;
  datalines;
ann 30
bob 45
cy  20
dee 55
;
run;
proc print data=d noobs;
  where age > 40;
run;
