/* Parenthesized array dimension `(n)` — SAS allows {n}/[n]/(n) (BUG-arrayparendim;
   real SDTM macro libraries use `array bits (&n) &varlist;`). The dim paren precedes the
   element list; the optional initial-value paren comes after, so position
   disambiguates the two (here `vals (3) v1-v3 (10 20 30)`). Element references
   still use {}/[] subscripts. */
data d;
  array bits (3) b1-b3;            /* paren dim + explicit element list */
  array vals (3) v1-v3 (10 20 30); /* paren dim, element list, then init list */
  do i = 1 to 3; bits{i} = i * 5; end;
  keep b1 b2 b3 v1 v2 v3;
run;
proc print data=d noobs; run;
