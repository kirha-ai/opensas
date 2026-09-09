/* QA tick377 cross-landing sweep — NOTE-reportgroupblank (ee0550a7) shape pins.
   That landing moved SEVEN goldens and its own fixture covers the two-group
   case. Base SAS 9.4 Procedures Guide, Seventh Edition, printed p.2094 (Group
   Variables): "PROC REPORT does not repeat the values of a group variable from
   one row to the next if the value does not change, unless a group variable to
   its left changes values." The "unless" clause is the whole rule, and these
   are the shapes the landing's fixture does NOT reach. Each was byte-compared
   against a baseline binary at aeac429a and re-verified on live master.

   Report 1  THREE group columns — the transitive case. When B changes, C must
             PRINT (a group variable to its left changed) even though C's own
             value repeats; when only C changes, B blanks. When A changes both
             B and C print.
   Report 2  BREAK AFTER / SUMMARIZE — the break line keeps the break value, and
             the first detail row after it re-prints because A changed.
   Report 3  BREAK BEFORE / SUMMARIZE — same, on the other side of the line.
   Report 4  RBREAK AFTER / SUMMARIZE — the grand-total line is not a detail row
             and carries no group value to blank.
   Report 5  DESCENDING group — blanking follows the SORTED order, not the input
             order.
   Report 6  NUMERIC group columns — blanking is on the formatted value, so it
             applies to numerics identically.
   Report 7  Column order swapped — "to its left" means REPORT-column order, not
             DEFINE order or data set order.
   Report 8  Single group column — every level is distinct by construction, so
             nothing blanks (the landing's byte-identity claim). */

data t; input a $ b $ c $ n; datalines;
X P 1 10
X P 2 20
X Q 1 30
X Q 2 40
Y P 1 50
Y P 2 60
;
run;

/* 1: three group columns */
proc report data=t nowd;
  column a b c n;
  define a / group; define b / group; define c / group;
  define n / analysis sum;
run;

data u; input a $ b $ n; datalines;
X P 1
X Q 2
Y P 3
Y Q 4
;
run;

/* 2: BREAK AFTER / SUMMARIZE */
proc report data=u nowd;
  column a b n;
  define a / group; define b / group;
  define n / analysis sum;
  break after a / summarize;
run;

/* 3: BREAK BEFORE / SUMMARIZE */
proc report data=u nowd;
  column a b n;
  define a / group; define b / group;
  define n / analysis sum;
  break before a / summarize;
run;

/* 4: RBREAK AFTER / SUMMARIZE */
proc report data=u nowd;
  column a b n;
  define a / group; define b / group;
  define n / analysis sum;
  rbreak after / summarize;
run;

/* 5: DESCENDING group */
proc report data=u nowd;
  column a b n;
  define a / group descending; define b / group;
  define n / analysis sum;
run;

/* 6: numeric group columns */
data v; input a b n; datalines;
1 7 10
1 8 20
2 7 30
;
run;
proc report data=v nowd;
  column a b n;
  define a / group; define b / group;
  define n / analysis sum;
run;

/* 7: swapped column order — "to its left" is REPORT-column order */
data w; input a $ b $ n; datalines;
X P 1
X P 2
Y P 3
;
run;
proc report data=w nowd;
  column b a n;
  define b / group; define a / group;
  define n / analysis sum;
run;

/* 8: single group column — nothing to blank */
proc report data=w nowd;
  column a n;
  define a / group;
  define n / analysis sum;
run;
