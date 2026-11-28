/* STAT-MIANALYZE-001: default PROC MIANALYZE listing (Model Information,
 * Variance Information, Parameter Estimates) for both DATA= forms: the EST
 * form (_TYPE_ PARMS/COV observations per _Imputation_, as a regression
 * OUTEST= COVOUT data set) and the estimates-with-STDERR form, then ALPHA=,
 * EDF= and THETA0=. Layout follows the SAS/STAT 15.4 reference listing; the
 * numbers are hand arithmetic from Rubin's rules. Invented data.
 */
data outest;
input _Imputation_ _TYPE_ $ _NAME_ :$9. Intercept Dose;
datalines;
1 PARMS .         90.5   -3.10
1 COV   Intercept 81     -0.5
1 COV   Dose      -0.5   0.1296
2 PARMS .         94.0   -2.80
2 COV   Intercept 72.25  -0.5
2 COV   Dose      -0.5   0.1156
3 PARMS .         96.5   -3.30
3 COV   Intercept 90.25  -0.5
3 COV   Dose      -0.5   0.1444
4 PARMS .         89.0   -2.90
4 COV   Intercept 64     -0.5
4 COV   Dose      -0.5   0.1024
;
run;
proc mianalyze data=outest;
modeleffects Intercept Dose;
run;
data fits;
input Intercept SeInt Dose SeDose;
datalines;
90.5 9.0 -3.10 0.36
94.0 8.5 -2.80 0.34
96.5 9.5 -3.30 0.38
89.0 8.0 -2.90 0.32
;
run;
proc mianalyze data=fits;
modeleffects Intercept Dose;
stderr SeInt SeDose;
run;
proc mianalyze data=fits alpha=0.1 edf=28 theta0=90 -3;
modeleffects Intercept Dose;
stderr SeInt SeDose;
run;
