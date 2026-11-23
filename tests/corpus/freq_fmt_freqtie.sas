/* SAS 9.4M9 orders tied counts by the displayed VALUE labels:
   Aaa, Mmm, Zzz. The second table orders unequal counts from high to low. */
data d;
  input x @@;
  datalines;
1 2 3 1 2 3
;
run;
proc format; value lf 1='Zzz' 2='Aaa' 3='Mmm'; run;
proc freq data=d order=freq;
  format x lf.;
  tables x;
run;
data e;
  input x @@;
  datalines;
2 2 2 1 1 3
;
run;
proc freq data=e order=freq;
  format x lf.;
  tables x;
run;
