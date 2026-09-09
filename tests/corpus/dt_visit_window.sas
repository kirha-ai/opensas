data visits;
  length subjid $4;
  input subjid $ vy vm vd;
  datalines;
S001 2020 1 1
S001 2020 1 20
S001 2020 3 5
S002 2020 2 10
;
run;
data _null_;
  set visits;
  by subjid;
  retain base;
  vdt = mdy(vm, vd, vy);
  if first.subjid then base = vdt;
  window = vdt - base;
  put subjid "window_days=" window;
run;
