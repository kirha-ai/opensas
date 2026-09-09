data d;
  input dt mmddyy10. tm time8.;
  datalines;
12/25/2024 13:30:00
;
run;
proc print data=d noobs; run;
