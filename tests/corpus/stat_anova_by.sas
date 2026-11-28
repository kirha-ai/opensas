/* STAT-ANOVA-001: PROC ANOVA BY-group boundaries and per-group pages.
 * Data: published SAS/STAT 15.4 ch.29 Clover sample, duplicated into two
 * BY groups. Printed values were checked token-for-token against the SAS
 * listing of the same analysis; MEANS output belongs to later tickets. */
options nodate nonumber nocenter linesize=160;
title1 'Nitrogen Content of Red Clover Plants';
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
data _oracle_input; set Clover; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc anova data = _oracle_input;
by _oracle_by;
class Strain;
model Nitrogen = Strain;
run;
