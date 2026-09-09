/* FINDC k modifier = complement: first char NOT in the list/classes.
   Regression guard for BUG-findckmod. */
data _null_;
  a = findc("abc123", "abc", "k");
  b = findc("abc123", "123", "k");
  c = findc("   x", " ", "k");
  d = findc("abc123", "abc");
  e = findc("aaa", "abc", "k");
  put "kc1=" a;
  put "kc2=" b;
  put "kc3=" c;
  put "nok=" d;
  put "allin=" e;
run;
