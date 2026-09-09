/* BUG-setbyvarlen: SET+BY must compare last./the sortedness check against the
   SAME length-truncated BY value that first./the PDV use (twin of
   BUG-mergebyvarlen). g is read $2 but the step declares LENGTH $1, so every
   value truncates to its first char: 'AB','AC','AD' all become 'A' = ONE group.
   Before the fix last./sortedness saw the RAW value and split spurious groups
   (wrong last., wrong row count) or errored "not properly sorted". */

/* Repro A — char BY, short LENGTH: three raw-distinct keys collide into one
   group. Correct flags: first.=1,0,0 last.=0,0,1 → one last. row. */
data dA; length g $2; input g $ x; datalines;
AB 1
AC 2
AD 3
;
run;
data _null_; length g $1; set dA; by g;
  put "A g=" g "x=" x "first=" first.g "last=" last.g;
run;

/* Repro B — raw order INVERTS inside the truncated group (AB,AC,AA). Truncated
   keys are A,A,A → perfectly sorted; no spurious "not properly sorted" ERROR. */
data dB; length g $2; input g $ x; datalines;
AB 1
AC 2
AA 3
;
run;
data _null_; length g $1; set dB; by g;
  put "B g=" g "x=" x "first=" first.g "last=" last.g;
run;

/* Repro C — numeric LENGTH variant (GH#46 byte-truncation): length x 3 makes
   1.0001 and 1.0002 collide (one group), 1.0003 truncates apart (own group). */
data dC; input x y; datalines;
1.0001 1
1.0002 2
1.0003 3
;
run;
data _null_; length x 3; set dC; by x;
  put "C x=" x "y=" y "first=" first.x "last=" last.x;
run;

/* Control — equal-length BY ($2, no truncation): distinct keys stay distinct,
   three singleton groups, each first.=last.=1. Unchanged by the fix. */
data dE; length g $2; input g $ x; datalines;
AB 1
AC 2
AD 3
;
run;
data _null_; length g $2; set dE; by g;
  put "E g=" g "x=" x "first=" first.g "last=" last.g;
run;
