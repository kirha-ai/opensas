/* STAT-CATMOD-004 MODEL / RESPONSE / Specification of Effects (PDF pp.
   2201-2226): a RESPONSE row of numeric coefficients (linear response
   function sum_j a_j p_ij, scores 1 2 3 and indicator 1 0 0 / 1 0 0 0,
   analysed by WLS); MODEL options FREQ (Response Frequencies), PROB
   (Response Probabilities) for 2, 3 and 4 response levels, CLPARM (95%
   Wald limits, small limits as 0.00248), NOPROFILE (no population or
   response profiles), DESIGN; the bar operator g|h and A|B|C (A B A*B C
   A*C B*C A*B*C); effect names over 24 characters shortened (longest
   variable name, leftmost of equals, loses a character until it fits);
   a saturated model's Residual row (0 DF, '.').
   Expected listing: SAS 9.4 reference run of this program (2026-11-28),
   trailing blanks trimmed. Data: invented. */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title;
data t3;
input g $ h $ y $ w @@;
datalines;
a p r1 10 a p r2 20 a p r3 15
a q r1 12 a q r2 9 a q r3 30
b p r1 25 b p r2 14 b p r3 11
b q r1 8 b q r2 17 b q r3 22
;
proc catmod data=t3;
weight w;
response 1 2 3;
model y = g h / freq prob clparm noprofile;
run;
response 1 0 0;
model y = g|h / freq prob design;
run;
quit;
data t4;
input LongVarNameAlpha $ Bb $ LongerVariableNameBeta $ y $ w @@;
datalines;
a p u r1 10 a p u r2 20 a p v r1 15 a p v r2 9
a q u r1 12 a q u r2 9 a q v r1 30 a q v r2 11
b p u r1 25 b p u r2 14 b p v r1 11 b p v r2 13
b q u r1 8 b q u r2 17 b q v r1 22 b q v r2 16
;
proc catmod data=t4;
weight w;
response 1 0;
model y = LongVarNameAlpha|Bb|LongerVariableNameBeta / freq prob noprofile;
run;
quit;
data t5;
input g $ y $ w @@;
datalines;
a r1 10 a r2 20 a r3 15 a r4 5
b r1 12 b r2 9 b r3 30 b r4 7
;
proc catmod data=t5;
weight w;
response 1 0 0 0;
model y = g / freq prob;
run;
quit;
