/* Split a datetime into its date and time parts (DATEPART/TIMEPART) */
data vs;
  input USUBJID $ VSDTC $18.;
  datalines;
01-001 15JAN2024:08:30:00
01-002 20JAN2024:14:15:00
;
run;
data d;
  set vs;
  dtm = input(VSDTC, datetime18.);
  vdate = datepart(dtm);
  vtime = timepart(dtm);
  format vdate date9. vtime time8.;
run;
proc print data=d; var USUBJID vdate vtime; run;
