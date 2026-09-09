/* BUG-univignoresby (QA tick395 cross-landing sweep, MED silent-wrong): PROC
   UNIVARIATE parsed BY and then IGNORED it — the listing printed ONE pooled
   Moments block over ALL obs (Mean 82.5 below), formatted exactly like the
   per-group answer asked for, no NOTE, exit 0. The fix drives the listing
   through the SAME BY machinery MEANS uses (decodeProcBy + bySlices +
   appendByLine), so listing and OUTPUT OUT= cannot disagree.

   DOC: SAS 9.4 Statistical Procedures, the UNIVARIATE chapter (this volume
   numbers its pages in a RUNNING HEADER, e.g. "410 ! Chapter 4: The UNIVARIATE
   Procedure" — the printed number is NOT the PDF index): "BY Statement"
   printed p.410 — "You can specify a BY statement with PROC UNIVARIATE to
   obtain separate analyses of observations in groups that are defined by the
   BY variables" — and "the observations in the input data set must be sorted
   in ascending order" (the same page's sortedness requirement; its ERROR text
   is the shared 'Data set X is not sorted in ascending sequence' this repo
   already uses for MEANS/TRANSPOSE, per NOTE-procsortguards).

   ARM 1 — the bug itself: two BY groups on the LISTING, each headed by its
   BY value (g=1 Mean 15, g=2 Mean 150; pooled was 82.5).
   ARM 2 — BY DESCENDING: the listing order follows the BY's own direction,
   matching the OUT= row order 9fddfd73/f787ccb8 pinned (means_out_by_descending).
   ARM 3 — a two-variable BY: one block set per (g,h) combination.
   ARM 4 — OUTPUT OUT= under BY still works: one summary row per BY group,
   in the SAME order as the listing (both are the input's group order).
   ARM 5 — the control: NO BY. The pooled single block must not move a byte.
   (The unsorted-input ERROR is pinned in proc.zig's in-file test via the
   captured diagnostics reporter — it must not run as a passing fixture.) */

data a; input g x @@; datalines;
1 10  1 20  2 100  2 200
;
run;
proc sort data=a; by g; run;

/* ARM 1 */
proc univariate data=a; by g; var x; run;

/* ARM 5 (control — runs FIRST would hide a regression behind the BY blocks;
      LAST it pins that the pooled path is untouched) */
proc univariate data=a; var x; run;

/* ARMs 2+3+4: DESCENDING + two-variable BY + OUT= under BY, one program. */
data d; input g h x @@; datalines;
2 2 100  2 1 200  1 2 10  1 1 20
;
run;
proc sort data=d; by descending g h; run;
proc univariate data=d; by descending g h; var x; output out=o mean=m n=n; run;
proc print data=o noobs; run;
