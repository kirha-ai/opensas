/* PERF-tabulatecross correctness fixture: the one-pass cell bucketing must be
   byte-identical to the old nr×nc×N per-cell rescan. Covers what the other
   TABULATE fixtures don't: empty (ri,ci) cells, case-mixed levels (eqi dedup),
   non-accumulable stats (median/std), and N/PCTN with no analysis var.
   (A quadratic-sized perf probe would be too slow for the corpus.)
   First table also pins per-element stat lists (GAP-tabulateforms #7): the
   prod levels carry only their own 7 stats, the All block only its (sum
   pctsum) — the old union rendered all 8 under every block. */
data d;
  input reg $ prod $ amt;
  datalines;
East A 10
EAST A 20
East B 30
West A 40
West A 50
;
run;
/* (West,B) is an empty cell; East/EAST collapse to one level (case-insensitive). */
proc tabulate data=d;
  class reg prod;
  var amt;
  table reg all, prod*amt*(n sum mean min max median std) all*amt*(sum pctsum);
run;
/* no analysis var: N/PCTN frequency cross. */
proc tabulate data=d;
  class reg prod;
  table reg, prod*(n pctn);
run;
data n;
  input trt phase resp;
  datalines;
1 1 5
1 2 7
2 1 9
2 2 11
2 2 13
;
run;
/* numeric × numeric class cross. */
proc tabulate data=n;
  class trt phase;
  var resp;
  table trt all, phase*resp*(sum mean) all*resp*sum;
run;
