/* BUG-transposeidfmt: PROC TRANSPOSE names ID columns from the FORMATTED ID
   value (SAS 9.4 ID statement), not the raw value. A numeric date ID with
   format date9. names `_01JAN2020`, not `_21915`; an unformatted numeric ID
   keeps the raw-value name (`_1`, tick208-verified). */
data d;
  input dt v;
  datalines;
21915 100
21916 200
;
run;
data d2; set d; format dt date9.; run;
proc transpose data=d2 out=w_fmt; id dt; var v; run;
proc print data=w_fmt noobs; run;
proc transpose data=d out=w_raw; id dt; var v; run;
proc print data=w_raw noobs; run;
