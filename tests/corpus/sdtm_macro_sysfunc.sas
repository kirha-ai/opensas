/* Convert a date at macro-compile time with %SYSFUNC(INPUTN/PUTN) */
%let d  = %sysfunc(inputn(15JAN2024, date9.));
%let iso = %sysfunc(putn(&d, yymmdd10.));
data d;
  sasday = &d;
  length isodate $10;
  isodate = "&iso";
run;
proc print data=d; var sasday isodate; run;
