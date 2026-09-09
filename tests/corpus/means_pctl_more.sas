data d;
  do i = 1 to 100; x = i; output; end;
run;
proc means data=d p5 p10 p90 p95 qrange; var x; run;

data m;
  input x @@;
  datalines;
2 4 4 4 5 5 7 9
;
run;
proc means data=m mode css uss median; var x; run;
