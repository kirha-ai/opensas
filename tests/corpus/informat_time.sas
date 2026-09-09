/* BUG-timeinformat + BUG-hhmmssinformat: TIMEw. reads AM/PM, the `.` field
   separator, and fractional seconds; HHMMSSw. reads colon AND digit-packed
   forms. Hand arithmetic (SAS time = seconds since midnight):
     1:30:00 PM = (1+12)*3600 + 30*60       = 48600   (PM adds 12h)
     01:30:45.5 = 1*3600 + 30*60 + 45.5     = 5445.5  (fraction kept)
     12.56      = 12*3600 + 56*60           = 46560   (period = separator)
     1:13 pm    = 13*3600 + 13*60           = 47580
     12:00 AM   = 0                         (12 AM is hour 0)
     12:00 PM   = 12*3600                   = 43200   (12 PM stays 12)
     packed 013045 hhmmss6. = 01:30:45      = 5445
     packed 124    hhmmss8. = 012400        = 5040    (left 0-padded)
     13:30:45    hhmmss8. (colon form)      = 48645   (fraction ignored) */
data _null_;
  a = input("1:30:00 PM", time11.);
  b = input("01:30:45.5", time11.);
  c = input("12.56", time10.);
  d = input("1:13 pm", time10.);
  e = input("12:00 AM", time10.);
  f = input("12:00 PM", time10.);
  g = input("013045", hhmmss6.);
  h = input("124", hhmmss8.);
  i = input("13:30:45", hhmmss8.);
  /* E8601DT keeps the fraction: 2020-03-17 = SAS day 21991;
     21991*86400 + 52215.5 = 1900074615.5 (was truncated to midnight) */
  j = input("2020-03-17T14:30:15.5", e8601dt22.);
  put a b c d e f g h i j;
run;
/* The INPUT-statement path reads the same values from datalines (blank-free
   fields: a NAMED numeric informat still takes the whitespace token list read). */
data t;
  input t time11.;
  datalines;
01:30:45.5
13:30:00
;
run;
data h;
  input h hhmmss6.;
  datalines;
013045
;
run;
proc print data=t noobs; run;
proc print data=h noobs; run;
