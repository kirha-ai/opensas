/* BUG-tabulatespecialmiss: PROC TABULATE with a CLASS var holding SPECIAL
   MISSING values (.a-.z, ._) must keep each distinct payload as its own level
   (.a->A, .b->B, ._->_ , plain .->.) — it used to collapse them all into one
   `.` level, merging their N/Sum. Ordering: ._ < . < .a < .b < ... < numbers.
   With `/ missing` the special-missing levels are kept; without it (as in SAS)
   any obs missing on the class var is excluded. */
data g;
  input g v;
  datalines;
1 10
.a 20
1 30
.b 40
;
run;
/* MISSING keeps .a and .b as their own levels A and B (ordered before 1):
   A -> N=1 Sum=20, B -> N=1 Sum=40, 1 -> N=2 Sum=40 (10+30). */
proc tabulate data=g missing; class g; var v; table g, v*(n sum); run;
