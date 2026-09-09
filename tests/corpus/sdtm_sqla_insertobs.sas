/* &SQLOBS reflects the number of rows an INSERT added */
data ex; input USUBJID $ DOSE; datalines;
01-001 50
01-002 100
;
run;
proc sql;
  insert into ex values("01-003", 75) values("01-004", 25) values("01-005", 60);
quit;
data added;
  n = &sqlobs;
run;
proc print data=ex; run;
proc print data=added; var n; run;
