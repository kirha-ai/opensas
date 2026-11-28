/* STAT-GENMOD-002: PROC GENMOD Normal distribution with a log link and the
   scale estimated by maximum likelihood (SAS/STAT 15.4 ch.51, Getting Started
   default path; example "Normal Regression, Log Link").
   Data: the published sample of that example. The expected listing is the SAS
   listing for this model: Model Information, Number of Observations, Criteria
   For Assessing Goodness Of Fit, convergence line, Analysis Of Maximum
   Likelihood Parameter Estimates and the scale NOTE.
   Second step: the same data in two identical BY groups, so each group must
   repeat the same tables under its own BY line.
   Known whitespace-only difference: opensas centers the BY line even under
   NOCENTER (shared BY-line helper); SAS prints it flush left. */
options nocenter;
title;
data nor;
input x y;
datalines;
0 5
0 7
0 9
1 7
1 10
1 8
2 11
2 9
3 16
3 13
3 14
4 25
4 24
5 34
5 32
5 30
;
proc genmod data=nor;
model y = x / dist = normal
link = log;
run;
data _oracle_input; set nor; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc genmod data=_oracle_input;
by _oracle_by;
model y = x / dist = normal link = log;
run;
