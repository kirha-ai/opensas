data _null_;
  input d date9. / e yymmdd10.;
  put "d=" d " e=" e;
datalines;
31FEB2020
2020-02-31
15JAN2020
2020-02-29
;
run;
