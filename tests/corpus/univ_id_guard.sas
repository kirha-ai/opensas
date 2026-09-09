/* BUG-univclass (ID half): PROC UNIVARIATE ID labels extreme observations — a table
   opensas does not print — and was silently swallowed by the same `else i+=1` as
   CLASS. Must fail LOUD (ERROR, run halts, stdout empty) instead of ignoring it.
   The PROC PRINT is a regression tripwire: removing the guard leaks the listing.
   expect-rc: 2 */
data d;
  x = 1;
run;

proc univariate data=d;
  id x;
  var x;
run;

proc print data=d;
run;
