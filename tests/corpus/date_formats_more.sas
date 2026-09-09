data _null_;
  d = mdy(7, 4, 2020);
  t = 45045;
  put d ddmmyy10.;
  put d yymmdd10.;
  put t time8.;
  put d worddate.;
run;
