/* BUG-outdsobsslice: obs=/firstobs= are INPUT-only dataset options. On an
   OUTPUT dataset SAS ignores them and writes ALL rows (applying the slice there
   silently dropped output rows). WHERE= on an output dataset IS still honored.
   Input-side obs=/firstobs= on a SET still slice the read. */
data src;
  input v;
  datalines;
10
20
30
40
;
run;

/* obs= on OUTPUT: ignored, all 4 rows written */
data o_obs(obs=2);
  set src;
run;
proc print data=o_obs; run;

/* firstobs= on OUTPUT: ignored, all 4 rows written */
data o_first(firstobs=3);
  set src;
run;
proc print data=o_first; run;

/* firstobs=/obs= on INPUT (SET): slices to rows 2..3 */
data i_slice;
  set src(firstobs=2 obs=3);
run;
proc print data=i_slice; run;

/* WHERE= on OUTPUT: still honored */
data o_where(where=(v>20));
  set src;
run;
proc print data=o_where; run;
