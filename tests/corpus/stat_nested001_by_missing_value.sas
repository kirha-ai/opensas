/* STAT-NESTED-001: a missing BY variable value forms its own BY group (it
 * is not an omitted observation), listed first in ascending order. Invented
 * data (D-011); the expected listing is a SAS 15.4 reference run of this
 * program, with the blank line SAS writes before each new page title dropped.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data d; input g a b y @@; datalines;
. 1 1 3 . 1 1 5 . 1 2 4 . 1 2 8 . 2 1 6 . 2 1 7 . 2 2 2 . 2 2 4
1 1 1 9 1 1 1 5 1 1 2 6 1 1 2 6 1 2 1 1 1 2 1 3 1 2 2 7 1 2 2 5
;
title 'T1 missing BY value';
proc nested data=d; by g; class a b; var y; run;
