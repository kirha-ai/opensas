data arms; length subjid $4 arm $8; input subjid $ arm $; datalines;
S001 Active
S002 Placebo
;
run;
data ae; length subjid $4 aeterm $10; input subjid $ aeterm $; datalines;
S001 Headache
S001 Nausea
S002 Fatigue
;
run;
data _null_;
  merge ae(in=a) arms;
  by subjid;
  if a;
  put subjid arm aeterm;
run;
