/* expect-rc: 2
   STAT-INBREED-001 boundary: the User's Guide monoecious population
   (Example 71.1; published sample data) assigns the non-dyadic covariance
   1.135. SAS 9.4 prints coefficients derived from such values one unit low
   in the fourth decimal (1.135 shows as 1.1349) by a rule opensas has not
   identified, so the step must fail visibly (D-009 gap) instead of printing
   the exactly rounded 1.1350. */
options nocenter;
title;
data Monoecious;
   input Generation Individual Parent1 Parent2 Covariance @@;
   datalines;
1 1 . . .      1 2 . . .       1 3 . . .
2 1 1 1 .      2 2 1 2 .       2 3 2 3 .
3 1 1 2 .      3 2 1 3 .       3 3 2 1 .
3 4 1 3 .      3 . 2 3 0.50    3 . 4 3 1.135
;
proc inbreed ind covar matrix data=Monoecious;
   class Generation;
run;
