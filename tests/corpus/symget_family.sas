/* QA regression (BUG-symgetlet fixed): SYMGET/SYMEXIST see %let AND CALL SYMPUT
   vars (unified table); SYMGLOBL/SYMLOCAL scope checks. */
%let gv = letval;
data _null_;
  call symput("cv", "world");
  a = symget("gv");
  b = symget("cv");
  c = symexist("gv");
  d = symexist("nope");
  e = symglobl("gv");
  f = symlocal("gv");
  put "symget_let=" a;
  put "symget_put=" b;
  put "symexist_yes=" c;
  put "symexist_no=" d;
  put "symglobl=" e;
  put "symlocal=" f;
run;
