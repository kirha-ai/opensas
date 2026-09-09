/* numeric_format: F / COMMA / DOLLAR write formats (grouping + currency). Phase-G. */
data _null_;
  n = 1234567.89;
  put "F="      n comma12.2;
  put "COMMA="  n comma14.2;
  put "DOLLAR=" n dollar14.2;
run;
