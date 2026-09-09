/* BUG-mergenobymissing (Language Reference: Concepts p.110): a one-to-one MERGE with NO BY sets an
   exhausted source's vars to MISSING (unlike a match-merge, which holds the last
   value). a=1,2,3 / b=10,20 → row3 y=. (not the held 20). */
data a;
  input x;
  datalines;
1
2
3
;
run;
data b;
  input y;
  datalines;
10
20
;
run;
data out;
  merge a b;
run;
proc print data=out noobs; run;
