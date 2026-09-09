data one;
  input a b c;
  datalines;
10 20 30
;
run;
proc transpose data=one out=flipped;
  var a b c;
run;
proc print data=flipped noobs; run;
