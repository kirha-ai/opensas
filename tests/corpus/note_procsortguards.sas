/* NOTE-procsortguards: RANK and STANDARD now run the shared MEANS/TRANSPOSE/
   UNIVARIATE sortedness guard (BUG-meansbyunsorted) — an unsorted BY ERRORs
   "Data set X is not sorted in ascending sequence." instead of silently
   splitting a repeated key into contiguous runs and ranking/standardizing
   within each run (plausible-looking WRONG numbers at exit 0). The fail-loud
   arms (incl. BY DESCENDING and the no-OUT= assertion) are pinned in-file in
   src/proc.zig via the captured diagnostics reporter; this fixture pins the
   CORRECT sorted-BY values, a BY DESCENDING arm, and non-BY controls that
   must not move.
   expect-rc: 1 */
data a; input g x @@; datalines;
1 2  1 4  1 6  2 10  2 20  2 30
;
run;
/* per-group ranks: g=1 -> 1 2 3, g=2 -> 1 2 3 */
proc rank data=a out=r; by g; var x; ranks rx; run;
proc print data=r noobs; run;
/* per-group z-scores: {2,4,6} mean 4 std 2 -> -1 0 1;
   {10,20,30} mean 20 std 10 -> -1 0 1 */
proc standard data=a out=sz mean=0 std=1; by g; var x; run;
proc print data=sz noobs; run;
/* BY DESCENDING on descending-sorted data: the guard flips per key, groups
   rank/standardize in the data's own order. g=2 {10,20,30} -> ranks 1 2 3,
   z -1 0 1; g=1 {5} is n<2 -> std undefined -> the target mean 0. */
data ad; input g x @@; datalines;
2 10  2 20  2 30  1 5
;
run;
proc rank data=ad out=rd; by descending g; var x; ranks rx; run;
proc print data=rd noobs; run;
proc standard data=ad out=sd mean=0 std=1; by descending g; var x; run;
proc print data=sd noobs; run;
/* non-BY controls — pooled ranks 1..6 and z-scores -1 0 1, guard untouched */
proc rank data=a out=rp; var x; ranks rx; run;
proc print data=rp noobs; run;
data c; input v @@; datalines;
2 4 6
;
run;
proc standard data=c out=cz mean=0 std=1; var v; run;
proc print data=cz noobs; run;
/* fail-loud tripwire: `ad` is DESCENDING-sorted, so plain `by g` must ERROR
   and stop the run — if the RANK guard is ever removed, the bogus per-run
   ranks below leak to stdout and this fixture goes red (rank_guards
   precedent; the per-proc unsorted arms are pinned in-file in src/proc.zig). */
proc rank data=ad out=bad; by g; var x; ranks rx; run;
proc print data=bad noobs; run;
