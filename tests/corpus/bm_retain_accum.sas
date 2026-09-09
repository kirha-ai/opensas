data dose; length subjid $4; input subjid $ amt; datalines;
S001 10
S001 10
S001 20
S002 5
S002 5
;
run;
data _null_;
  set dose;
  by subjid;
  retain cum;
  if first.subjid then cum = 0;
  cum + amt;
  put subjid "amt=" amt "cumulative=" cum;
run;
