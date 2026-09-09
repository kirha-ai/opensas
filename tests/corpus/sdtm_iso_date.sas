/* ISO-8601 date parse then re-emit (yymmdd round-trip) */
data raw;
  input ISODT $10.;
  datalines;
2024-01-15
2024-12-31
;
run;
data d;
  set raw;
  dt = input(ISODT, yymmdd10.);
  length back $10;
  back = put(dt, yymmdd10.);
  yr = year(dt);
  mo = month(dt);
run;
proc print data=d; var ISODT dt back yr mo; run;
