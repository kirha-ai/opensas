/* STAT-INBREED-001: CLASS nonoverlapping generations.
   1) The User's Guide Getting Started population with CLASS Generation
      (Figure 71.2; published sample data): Jane is appended to generation 1
      unseen; observation 4 assigns Cov(Mark, Kelly) = 0.50 in generation
      1; Jim's covariance value on a defining observation is ignored.
   2) The User's Guide monoecious population (Example 71.1; published
      sample data) with the last assignment changed from 1.135 to 0.75 so
      the expected value is exact: in generation 3 the family of 2 (2 and 4,
      parents 1 and 3) gets Cov(., 3) = 0.75, overriding 0.50; individuals
      with parents 1,2 and 2,1 are separate families. Hand mathematics:
      Cov(1,2) = 2 (f11 + f13 + f21 + f23)/4 = (0.75 + 0.25 + 0.125)/2
      = 0.5625. */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
data Population;
   input Individual $ Parent1 $ Parent2 $
         Covariance Sex $ Generation;
   datalines;
Mark   George Lisa    .    M 1
Kelly  Scott  Lisa    .    F 1
Mike   George Amy     .    M 1
.      Mark   Kelly 0.50 . 1
David  Mark   Kelly   .    M 2
Merle  Mike   Jane    .    F 2
Jim    Mark   Kelly 0.50 M 2
Mark   Mike   Kelly   .    M 2
;
proc inbreed data=Population covar matrix init=0.25;
   class Generation;
run;
data Monoecious;
   input Generation Individual Parent1 Parent2 Covariance @@;
   datalines;
1 1 . . .      1 2 . . .       1 3 . . .
2 1 1 1 .      2 2 1 2 .       2 3 2 3 .
3 1 1 2 .      3 2 1 3 .       3 3 2 1 .
3 4 1 3 .      3 . 2 3 0.50    3 . 4 3 0.75
;
proc inbreed ind covar matrix data=Monoecious;
   class Generation;
run;
