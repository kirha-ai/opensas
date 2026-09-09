data a; x=1; output; x=2; output; x=3; output; run;
proc sql;
  create table b as select monotonic() as RECID, x from a;
quit;
proc print data=b noobs; run;
