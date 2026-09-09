/* &SQLOBS = rows the last SQL statement processed (incl. SELECT ... INTO, where
   the print is suppressed); &SQLRC = 0 on success (BUG-sqlobs) */
data d;
  input USUBJID $ AVAL;
  datalines;
01-001 10
01-002 20
01-003 30
01-004 40
;
run;
proc sql noprint;
  select AVAL into :vlist separated by "," from d;
quit;
data after_into;
  n   = &sqlobs;
  rc  = &sqlrc;
  length lst $20;
  lst = "&vlist";
run;
proc sql;
  select * from d where AVAL > 20;
quit;
data after_select;
  n = &sqlobs;
run;
proc sql;
  create table hi as select * from d where AVAL >= 30;
quit;
data after_create;
  n = &sqlobs;
run;
proc print data=after_into; var n rc lst; run;
proc print data=after_select; var n; run;
proc print data=after_create; var n; run;
