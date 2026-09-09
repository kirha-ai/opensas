/* NOTE-freqtablesfmt (doc-finder tick185 + tick167:176): a FORMAT on a PROC
   FREQ TABLES var (and a PROC MEANS CLASS var) groups + displays by the
   FORMATTED value — raw values sharing a label collapse into one level.
   `tables sex` (no format) is the raw-value control. */
data d;
  input age sex $ wt @@;
  datalines;
25 F 60 30 M 70 35 F 80 44 M 90 50 F 55 62 M 66
;
run;
proc format; value agf low-40='<=40' 41-high='>40'; run;
proc freq data=d;
  format age agf.;
  tables age;
  tables sex;
  tables sex*age;
run;
proc means data=d n mean;
  class age;
  format age agf.;
  var wt;
  output out=m n=na mean=ma;
run;
proc print data=m;
  var _TYPE_ _FREQ_ na ma;
run;
