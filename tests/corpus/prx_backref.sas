/* doc-finder tick133 (BUG-prxbackref): PRX backreferences \1-\9 are a documented
   SAS 9.4 Perl-regex feature. opensas parseEscape treated \<digit> as the literal
   digit, so a backreference pattern silently compiled to the WRONG pattern and
   never matched the intended repeated text (silent-wrong — clinical worst class).
   prxmatch returns the 1-based match start, 0 = no match. Expected = real SAS. */
data _null_;
  a=prxmatch('/(ab)\1/', 'zzababzz');   /* "abab" at col 3            */
  b=prxmatch('/(\w)\1/', 'hello');      /* doubled "ll" at col 3      */
  c=prxmatch('/(\w)\1/', 'world');      /* no doubled letter -> 0     */
  d=prxmatch('/(\d+)-\1/', '34-34');    /* equal numbers -> match @1  */
  e=prxmatch('/(\d+)-\1/', '34-56');    /* unequal -> 0               */
  put "abab=" a;
  put "dbl_hello=" b;
  put "dbl_world=" c;
  put "num_eq=" d;
  put "num_ne=" e;
run;
