data lb; length subjid $4; input subjid $ val; datalines;
S001 10
S001 20
S001 30
S002 5
S003 7
S003 14
;
run;
data _null_;
  set lb;
  by subjid;
  retain total 0 n 0;
  if first.subjid then do; total=0; n=0; end;
  total + val;
  n + 1;
  if last.subjid then put subjid "n=" n "sum=" total;
run;
