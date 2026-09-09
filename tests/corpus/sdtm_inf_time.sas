/* TIME informat -> seconds since midnight; TIME format renders it back */
data vs;
  input VSTPT $ raw $;
  t = input(raw, time8.);
  format t time8.;
  datalines;
PREDOSE 08:30:00
POSTDOSE 14:15:30
;
run;
proc print data=vs; var VSTPT t; run;
