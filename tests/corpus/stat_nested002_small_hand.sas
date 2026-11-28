/* STAT-NESTED-002: smaller balanced nested random-effects cases with an
 * independent manual calculation (invented data, D-011).
 * Three-stage: Batch(2) / Sample(2) / Assay(2), 2 replicates, N=16.
 *   Hand: mean 16.0625; SS Batch 95.0625, Sample 29.125, Assay 36.25,
 *   Error 26.5 (DF 1/2/4/8); EMS coefficients 8,4,2,1 (Batch), 4,2,1, 2,1;
 *   components s2_e=3.3125, s2_assay=(9.0625-3.3125)/2=2.875,
 *   s2_sample=(14.5625-9.0625)/4=1.375, s2_batch=(95.0625-14.5625)/8=10.0625,
 *   total 17.625; F 6.53 (p 0.1251, F(1,2) closed form 1-sqrt(x)),
 *   1.61 (p 0.3075, F(2,4)), 2.74 (p 0.1053, F(4,8)); SE mean
 *   sqrt(95.0625/16)=2.4375.
 * Two-stage: A(3) / B(2), 2 replicates, N=12.
 *   Hand: mean 7.8333; SS A 82.666667, B 35, Error 12 (DF 2/3/6);
 *   components s2_e=2, s2_B=(11.666667-2)/2=4.833333,
 *   s2_A=(41.333333-11.666667)/4=7.416667, total 14.25; F 3.54 (p 0.1622),
 *   5.83 (p 0.0327); SE mean sqrt(41.333333/12)=1.85592145.
 * Printed precision: SS/MS/components 6 decimals, F 2, Pr > F and percent
 * 4, mean and its standard error 8. The expected listing is a SAS 15.4 run
 * of this program and agrees with every hand value above.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data lab;
input Batch Sample Assay Y @@;
datalines;
1 1 1 10 1 1 1 12 1 1 2 11 1 1 2 15
1 2 1 14 1 2 1 13 1 2 2 18 1 2 2 16
2 1 1 20 2 1 1 17 2 1 2 19 2 1 2 22
2 2 1 15 2 2 1 16 2 2 2 21 2 2 2 18
;
title1 'Three-stage nested design';
proc nested data=lab;
class Batch Sample Assay;
var Y;
run;
data two;
input A B Y @@;
datalines;
1 1 4 1 1 6 1 2 9 1 2 7
2 1 8 2 1 10 2 2 15 2 2 13
3 1 5 3 1 7 3 2 6 3 2 4
;
title1 'Small two-stage nested design';
proc nested data=two;
class A B;
var Y;
run;
