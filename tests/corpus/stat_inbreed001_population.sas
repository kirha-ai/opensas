/* STAT-INBREED-001: the overlapping-population analysis of the SAS/STAT
   15.4 User's Guide (Getting Started, Figure 71.1; published sample data).
   No VAR statement: Individual Parent1 Parent2 are the first three
   unaddressed variables and Covariance the fourth. Unknown parents (George,
   Lisa, Scott, Amy, Jane) are inserted before their first progeny;
   observation 4 (missing individual) and observation 8 (Mark again) are
   skipped; Jim's covariance 0.50 fixes Cov(Mark, Kelly). INIT=0.25 gives an
   unknown coancestry of 0.125 (Cov 0.25, founder diagonal 1.125). */
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
run;
