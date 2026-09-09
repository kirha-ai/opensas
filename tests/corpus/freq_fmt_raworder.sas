/* BUG-freqfmtorder: a VALUE. format whose label text sorts differently from the
   underlying raw value. SAS ORDER=INTERNAL (the default) orders the collapsed
   groups by the SMALLEST raw value behind each label, NOT alphabetically by
   label — so 1='Small' 2='Medium' 3='Large' prints Small/Medium/Large (raw
   1/2/3), never the alphabetical Large/Medium/Small. Cumulative columns follow
   that raw order. `tables grp` (no format) is the raw-value control; PROC MEANS
   CLASS with the same format bands in raw order too. */
data d;
  input sz grp @@;
  datalines;
3 1 1 1 2 2 3 2 2 1 1 2 1 1
;
run;
proc format; value szf 1='Small' 2='Medium' 3='Large'; run;
proc freq data=d;
  format sz szf.;
  tables sz;
  tables grp;
run;
proc means data=d n mean;
  class sz;
  format sz szf.;
  var grp;
run;
