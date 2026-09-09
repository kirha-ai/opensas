data d;
  input g $ x;
  datalines;
a 10
a 20
b 30
;
run;

title 'SUMMARY default: no listing';

proc summary data=d;
  var x;
run;

title 'SUMMARY PRINT: listing appears';

proc summary data=d print;
  var x;
run;

title 'SUMMARY OUTPUT OUT=: silent, dataset created';

proc summary data=d;
  var x;
  output out=o mean=m;
run;

proc print data=o noobs;
run;

title 'MEANS still prints by default';

proc means data=d;
  var x;
run;
