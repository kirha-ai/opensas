/* STAT-GENMOD-003: PROC GENMOD events/trials binomial model with the logit
   link, a CLASS main effect in the GLM parameterization (last level is the
   reference, printed with DF 0) and likelihood-ratio confidence limits (LRCI).
   Data: the published sample of SAS/STAT 15.4 ch.51 Example 51.1 (Logistic
   Regression). The expected listing is the SAS listing for this step: Model
   Information, observation/event/trial counts, Class Level Information,
   Response Profile, Criteria For Assessing Goodness Of Fit (DF 18-6=12; AIC,
   AICC, BIC from the full log likelihood with 6 parameters and n=18),
   convergence line, parameter estimates and the fixed-scale NOTE. */
options nocenter;
title;
data drug;
input drug$ x r n @@;
datalines;
A .1 1 10 A .23 2 12 A .67 1 9
B .2 3 13 B .3 4 15 B .45 5 16 B .78 5 13
C .04 0 10 C .15 0 11 C .56 1 12 C .7 2 12
D .34 5 10 D .6 5 9 D .7 8 10
E .2 12 20 E .34 15 20 E .56 13 15 E .8 17 20
;
proc genmod data=drug;
class drug;
model r/n = x drug / dist = bin
link = logit
lrci;
run;
