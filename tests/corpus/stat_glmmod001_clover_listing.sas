/* STAT-GLMMOD-001: default PROC GLMMOD listing (Class Level Information,
 * observation counts, Parameter Definitions, Design Points) for the
 * published red clover sample data (S154 Getting Started), then OUTDESIGN=
 * with NOPRINT feeding PROC REG: the design-column labels ("Strain 3DOK1")
 * and the unit-coefficient dependency line "Col7 = Intercept - Col2 ...".
 * Tokens match the SAS 9.4 reference listing; whitespace is opensas layout.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'Nitrogen Content of Red Clover Plants';
data Clover;
input Strain $ Nitrogen @@;
datalines;
3DOK1 19.4 3DOK1 32.6 3DOK1 27.0 3DOK1 32.1 3DOK1 33.0
3DOK5 17.7 3DOK5 24.8 3DOK5 27.9 3DOK5 25.2 3DOK5 24.3
3DOK4 17.0 3DOK4 19.4 3DOK4 9.1 3DOK4 11.9 3DOK4 15.8
3DOK7 20.7 3DOK7 21.0 3DOK7 20.5 3DOK7 18.8 3DOK7 18.6
3DOK13 14.3 3DOK13 14.4 3DOK13 11.8 3DOK13 11.6 3DOK13 14.2
COMPOS 17.3 COMPOS 19.4 COMPOS 19.1 COMPOS 16.9 COMPOS 20.8
;
proc glmmod data=Clover;
class Strain;
model Nitrogen = Strain;
run;
proc glmmod data=Clover outdesign=CloverDesign noprint;
class Strain;
model Nitrogen = Strain;
run;
proc reg data=CloverDesign;
model Nitrogen = Col2-Col7;
run;
