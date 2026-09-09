/* doc-finder tick151: regression guard for CHARACTER-family edge behaviors
   verified SAS-9.4-correct during the tick151 audit (positions, blank/length
   handling, quoting). NOT a bug repro — these all match the SAS Functions
   Reference; pins them so a refactor can't silently regress them. */
data _null_;
  /* SUBSTRN: positions outside [1,len] are ignored, window still counts */
  a = substrn('abcde', 0, 3);  put "substrn_0_3=[" a "]";
  b = substrn('abcde', -1, 3); put "substrn_neg=[" b "]";
  /* SUBPAD: substring of given length, blank-padded past the end */
  length p $6; p = subpad('abc', 2, 4); put "subpad=[" p "]";
  /* ANY-class position semantics: default, start, backward(negative start) */
  c = anyalpha('123abc');   put "anyalpha=" c;
  d = anyalpha('a1b2', 2);  put "anyalpha_start=" d;
  e = anyalpha('a1b2', -4); put "anyalpha_back=" e;
  f = notalpha('abc12');    put "notalpha=" f;
  /* DEQUOTE collapses a doubled embedded quote */
  length g $10; g = dequote('"a""b"'); put "dequote=[" g "]";
  /* QUOTE keeps trailing blanks inside the quotes */
  length h $10; h = quote('hi '); put "quote=[" h "]";
  /* PROPCASE: apostrophe is NOT a default word delimiter */
  length i $12; i = propcase("o'brien"); put "propcase=[" i "]";
  /* VERIFY: first char not in the set */
  j = verify('abcx', 'abc'); put "verify=" j;
run;
