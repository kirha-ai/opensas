/* numeric_informat: COMMA / DOLLAR / plain w.d (implied decimals) read via input(). Phase-G. */
data _null_;
  a = input("1,234", comma6.);  put "COMMA="  a;
  b = input("$1,234", dollar7.); put "DOLLAR=" b;
  c = input("1234", 6.2);        put "WD="     c;
run;
