/* BUG-dateblanksep + BUG-inputdatestmtblank: the DATEw./MMDDYYw./DDMMYYw./YYMMDDw.
   informats accept BLANK-separated components — `16 mar 2012` under date11.,
   `03 15 2012` under mmddyy10. — as well as the packed and `/`-separated forms.
   Hand-verified SAS days (days since 01JAN1960 = 0, cross-checked with `date -u`):
     15MAR2012 = 19067   16MAR2012 = 19068
   `16 mar 12` (2-digit year) lands on 2012 via YEARCUTOFF=1926. */
data _null_;
  input d date11.;
  put "DATE11=" d;
datalines;
16 mar 2012
16mar2012
;
run;

data _null_;
  input d mmddyy10.;
  put "MMDDYY=" d;
datalines;
03 15 2012
03/15/2012
;
run;

data _null_;
  input d date9.;
  put "DATE9_2DIG=" d;
datalines;
16 mar 12
;
run;

data _null_;
  a = input("16 mar 2012", date11.);   put "FN_DATE=" a;
  b = input("15 03 2012", ddmmyy10.);  put "FN_DMY=" b;
  c = input("2012 03 15", yymmdd10.);  put "FN_YMD=" c;
run;
