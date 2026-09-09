data dm; length subjid $4 sex $1; input subjid $ sex $ age; datalines;
S001 M 40
S002 F 55
S003 M 62
;
run;
data lb; length subjid $4; input subjid $ chol; datalines;
S001 190
S002 210
;
run;
data vs; length subjid $4; input subjid $ bmi; datalines;
S001 24
S003 28
;
run;
data _null_;
  merge dm lb vs;
  by subjid;
  put subjid sex "age=" age "chol=" chol "bmi=" bmi;
run;
