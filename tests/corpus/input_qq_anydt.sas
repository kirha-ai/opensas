/* GAP-inputstmtqq + GAP-anydtinformat (doc-finder tick124).
   Part 1: INPUT stmt `?`/`??` error-suppression modifier parses (dropped —
   opensas INPUT is already silent-missing on bad data, so 'abc' reads x=.
   with no ERROR). Part 2: ANYDTDTEw./ANYDTDTMw./ANYDTTMEw. informats read
   "any" date/datetime/time form. 15JAN2020 = SAS day 21929. */
data _null_;
  infile datalines;
  input x ?? 3.;
  put "QQ=" x;
datalines;
abc
;
run;

data _null_;
  infile datalines;
  input d anydtdte9.;
  put "ANYDTE=" d;
datalines;
15JAN2020
;
run;

data _null_;
  infile datalines;
  input m anydtdte10.;
  put "ANYMDY=" m;
datalines;
01/15/2020
;
run;

data _null_;
  infile datalines;
  input t anydtdtm19.;
  put "ANYDTM=" t;
datalines;
15JAN2020:10:30:00
;
run;

data _null_;
  infile datalines;
  input s anydttme8.;
  put "ANYTME=" s;
datalines;
10:30:00
;
run;

/* INPUT() function path must match the statement path (not silent-missing):
   whitelisting anydt in isKnownInformat would otherwise route the fn call to
   numFromSpec → missing. Manager safety guard. */
data _null_;
  a=input("15JAN2020",anydtdte9.); put "FNDTE=" a;
run;
