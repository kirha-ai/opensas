/* DATETIME informat -> seconds; split back with DATEPART/TIMEPART */
data vs;
  input raw $18.;
  dtm   = input(raw, datetime18.);
  vdate = datepart(dtm);
  vtime = timepart(dtm);
  format vdate date9. vtime time8.;
  datalines;
15JAN2024:08:30:00
20JAN2024:14:15:00
;
run;
proc print data=vs; var vdate vtime; run;
