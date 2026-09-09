/* NOTE-difcharnoterr + NOTE-callnohalt.
   DIF of a non-convertible CHARACTER value -> missing + the converted/
   invalid-data NOTE pair on stderr AND _ERROR_=1. An unsupported CALL
   routine reports its ERROR and ABORTS the step, so the statements after
   it never run. Valid DIF and a supported CALL MISSING are unchanged.
   expect-rc: 1 */
data _null_;
  input x @@;
  d = dif(x);
  put "valid-dif x=" x " d=" d;
  datalines;
10 14 19
;
run;

data _null_;
  c = 'abc';
  d = dif(c);
  put "difchar _error_=" _error_;
run;

data _null_;
  a = 1;
  b = 2;
  call missing(a, b);
  put "call-missing a=" a " b=" b;
run;

data _null_;
  call nosuchroutine(x);
  put "SHOULD NOT PRINT";
run;
