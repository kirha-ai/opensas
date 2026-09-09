data work.dm;
  length subjid $6;
  input subjid $ age;
  datalines;
S001 34
S002 51
;
run;
data work.vs;
  length subjid $6 param $4;
  input subjid $ param $ aval;
  datalines;
S001 SYS 120
S001 DIA 80
;
run;
proc contents data=work._all_; run;
