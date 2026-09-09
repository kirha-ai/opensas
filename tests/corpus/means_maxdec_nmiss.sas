data d;
  input v @@;
  datalines;
2 . 4 6 . 8
;
run;
proc means data=d n nmiss mean sum maxdec=2;
  var v;
run;
