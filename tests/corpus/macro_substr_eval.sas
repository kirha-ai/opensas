/* BUG-domainrows-empty: %substr/%scan must %eval arithmetic position/length args
   and match their close paren past a nested %length()/%str() (a study-day macro shape). */
%let v = ABCDEFG;
data _null_;
  a = "%substr(ABCDEFG,2,5-2)";           /* len 5-2=3 -> BCD */
  b = "%substr(&v,2,%length(&v)-3)";       /* len 7-3=4 -> BCDE */
  c = "%substr(ABCDEFG,1+1,3)";            /* pos 1+1=2 -> BCD */
  d = "%substr(HELLO,2,%length(HELLO))";   /* nested len, clamps -> ELLO */
  e = "%scan(a.b.c,2,%str(.))";            /* nested delim -> b */
  f = "%substr(HELLO,2,3)";                /* no nesting (regression) -> ELL */
  put "a=" a;
  put "b=" b;
  put "c=" c;
  put "d=" d;
  put "e=" e;
  put "f=" f;
run;
