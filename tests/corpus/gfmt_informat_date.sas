/* date_informat: DATE / YYMMDD / MMDDYY / DDMMYY read via input(). Phase-G. */
data _null_;
  a = input("04JUL2020", date9.);     put "DATE="   a;
  b = input("2020-07-04", yymmdd10.); put "YYMMDD=" b;
  c = input("07/04/2020", mmddyy10.); put "MMDDYY=" c;
  e = input("04/07/2020", ddmmyy10.); put "DDMMYY=" e;
run;
