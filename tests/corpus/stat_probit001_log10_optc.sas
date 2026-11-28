/* STAT-PROBIT-001: PROC PROBIT default listing for the events/trials normal
   model with LOG10 and OPTC (SAS/STAT 15.4 ch.100, Getting Started, p.8095):
   the dose-0 observation is the control group, enters the likelihood with
   p = C and seeds the initial natural response rate; the other 11
   observations are the model observations.
   Data: the published sample of that example.
   Expected: the SAS reference listing of this model. The reference program
   also requested PLOTS=(PREDPPLOT IPPPLOT) and OUTPUT OUT= P=; those are
   graphs and a data set, not listing tables, and stay loud gaps
   (stat_probit001_plots_output_gap). */
options nocenter;
title;
data study;
input Dose Respond @@;
Number = 15;
datalines;
0 3 1.1 4 1.3 4 2.0 3 2.2 5 2.8 4
3.7 5 3.9 9 4.4 8 4.8 11 5.9 12 6.8 13
;
proc probit data=study log10 optc;
model respond/number=dose;
run;
