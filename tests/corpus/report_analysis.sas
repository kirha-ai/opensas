/* BUG-reportanalysis (doc-finder tick136, MED silent-wrong): a PROC REPORT whose
   COLUMN list is ALL analysis variables (no group/order/display) must collapse to
   ONE summary row, default statistic SUM — opensas emitted one detail row per obs
   and ignored an explicit `define x / analysis sum`. Report 1: default SUM (6/60).
   Report 2: explicit analysis sum/mean (6/20). A char/display column would keep
   the detail report — that case is pinned by proc_report.sas. */
data d;
  input x y;
  datalines;
1 10
2 20
3 30
;
run;

proc report data=d nowd;
  column x y;
run;

proc report data=d nowd;
  column x y;
  define x / analysis sum 'Total X';
  define y / analysis mean 'Mean Y';
run;
