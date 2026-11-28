/* STAT-PROBIT-001: PROC PROBIT BY statement (SAS/STAT 15.4 ch.100, p.8105).
   Two explicit BY groups hold identical inputs (the published Getting Started
   sample), so each group must repeat the full listing under its own BY line.
   Expected: the SAS reference listing of this model per BY group (the
   reference program's PLOTS= and OUTPUT requests are separate loud gaps).
   Known whitespace-only difference: opensas centers the BY line even under
   NOCENTER (shared BY-line helper); SAS prints it flush left. */
options nocenter;
title;
data study;
input Dose Respond @@;
Number = 15;
datalines;
0 3 1.1 4 1.3 4 2.0 3 2.2 5 2.8 4
3.7 5 3.9 9 4.4 8 4.8 11 5.9 12 6.8 13
;
data _oracle_input; set study; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc probit data=_oracle_input log10 optc;
by _oracle_by;
model respond/number=dose;
run;
