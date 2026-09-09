data dm;
  length usubjid $4 sex $1 arm $8;
  input usubjid $ sex $ arm $ age;
  datalines;
S01 M Active 45
S02 F Placebo 60
;
run;
proc contents data=dm out=meta(keep=name type) noprint; run;
proc sort data=meta out=metao; by name; run;
proc print data=metao noobs; run;
