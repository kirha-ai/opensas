/* BUG-numxinformat: NUMXw.d reads the European convention — COMMA is the
   decimal separator, PERIOD the (ignored) grouping separator; mirror of
   COMMAw.d. Hand-verified: numx8.2 on '12,5' -> 12.5 (explicit decimal comma
   wins over d); on '1.234,56' -> 1234.56 (period dropped, comma = decimal);
   numx8. on '1.000' -> 1000 (period = thousands grouping, no decimals). */
data _null_;
  a = input("12,5", numx8.2);
  b = input("1.234,56", numx8.2);
  c = input("1.000", numx8.);
  put a= b= c=;
run;
data nx;
  input x numx8.2;
  datalines;
12,5
1.234,56
;
run;
proc print data=nx; run;
data ny;
  input y numx8.;
  datalines;
1.000
;
run;
proc print data=ny; run;
