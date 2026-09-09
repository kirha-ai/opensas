/* GAP-datasetsdeletecolon: PROC DATASETS `DELETE tmp_:;` is a name-prefix
   wildcard — delete every WORK member of the family, not a literal member
   named "tmp_" (a real EPOCH macro clears its TMP_ scratch family this way).
   Previously: "DELETE member not found", family left behind. */
data tmp_1; v = 1; run;
data tmp_2; v = 2; run;
data keeper; v = 9; run;

proc datasets library=work nolist;
  delete tmp_:;
quit;

data _null_;
  t1 = exist('tmp_1');   /* deleted -> 0 */
  t2 = exist('tmp_2');   /* deleted -> 0 */
  k  = exist('keeper');  /* untouched -> 1 */
  put t1= t2= k=;
run;
