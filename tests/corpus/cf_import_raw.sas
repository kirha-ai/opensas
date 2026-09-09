data labs;
  length subjid $4 test $6;
  input subjid $ test $ coldt date9. result comma8.;
  datalines;
S001 GLUC 01JAN2020 1,050
S002 ALT 15FEB2020 42
S003 CHOL 20MAR2020 2,300
;
run;
data _null_;
  set labs;
  length dc $10;
  dc = put(coldt, date9.);
  put subjid test "date=" dc "result=" result;
run;
