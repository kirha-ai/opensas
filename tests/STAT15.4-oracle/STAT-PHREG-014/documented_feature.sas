/* STAT-PHREG-014: PHREG — Hazard Ratios / HAZARDRATIO / Confidence Limits for a Hazard Ratio
 * Source: S154 / Chapter 92 / `Hazard Ratios` (PDF pp. 7409–7412); S154 / Chapter 92 / `HAZARDRATIO Statement` (PDF pp. 7364–7367); S154 / Chapter 92 / `Confidence Limits for a Hazard Ratio` (PDF pp. 7416–7418).
 * Discriminates: Example 92.13: Bayesian Analysis of the Cox Model; explicit statements: HAZARDRATIO
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc format; value yesno 0='no' 10='yes'; run;
data VALung;
drop check m;
retain Therapy Cell;
infile cards column=column;
length Check $ 1;
label Time='time to death in days'
Kps='Karnofsky performance scale'
Duration='months from diagnosis to randomization'
Age='age in years'
Prior='prior therapy'
Cell='cell type'
Therapy='type of treatment';
format Prior yesno.;
M=Column;
input Check $ @@;
if M>Column then M=1;
if Check='s'|Check='t' then do;
input @M Therapy $ Cell $;
delete;
end;
else do;
input @M Time Kps Duration Age Prior @@;
Status=(Time>0);
Time=abs(Time);
end;
datalines;
standard squamous
72 60 7 69 0 411 70 5 64 10 228 60 3 38 0 126 60 9 63 10
118 70 11 65 10 10 20 5 49 0 82 40 10 69 10 110 80 29 68 0
314 50 18 43 0 -100 70 6 70 0 42 60 4 81 0 8 40 58 63 10
144 30 4 63 0 -25 80 9 52 10 11 70 11 48 10
standard small
30 60 3 61 0 384 60 9 42 0 4 40 2 35 0 54 80 4 63 10
13 60 4 56 0 -123 40 3 55 0 -97 60 5 67 0 153 60 14 63 10
59 30 2 65 0 117 80 3 46 0 16 30 4 53 10 151 50 12 69 0
22 60 4 68 0 56 80 12 43 10 21 40 2 55 10 18 20 15 42 0
139 80 2 64 0 20 30 5 65 0 31 75 3 65 0 52 70 2 55 0
287 60 25 66 10 18 30 4 60 0 51 60 1 67 0 122 80 28 53 0
27 60 8 62 0 54 70 1 67 0 7 50 7 72 0 63 50 11 48 0
392 40 4 68 0 10 40 23 67 10
standard adeno
8 20 19 61 10 92 70 10 60 0 35 40 6 62 0 117 80 2 38 0
132 80 5 50 0 12 50 4 63 10 162 80 5 64 0 3 30 3 43 0
95 80 4 34 0
standard large
177 50 16 66 10 162 80 5 62 0 216 50 15 52 0 553 70 2 47 0
278 60 12 63 0 12 40 12 68 10 260 80 5 45 0 200 80 12 41 10
156 70 2 66 0 -182 90 2 62 0 143 90 8 60 0 105 80 11 66 0
103 80 5 38 0 250 70 8 53 10 100 60 13 37 10
test squamous
999 90 12 54 10 112 80 6 60 0 -87 80 3 48 0 -231 50 8 52 10
242 50 1 70 0 991 70 7 50 10 111 70 3 62 0 1 20 21 65 10
587 60 3 58 0 389 90 2 62 0 33 30 6 64 0 25 20 36 63 0
357 70 13 58 0 467 90 2 64 0 201 80 28 52 10 1 50 7 35 0
30 70 11 63 0 44 60 13 70 10 283 90 2 51 0 15 50 13 40 10
test small
25 30 2 69 0 -103 70 22 36 10 21 20 4 71 0 13 30 2 62 0
87 60 2 60 0 2 40 36 44 10 20 30 9 54 10 7 20 11 66 0
24 60 8 49 0 99 70 3 72 0 8 80 2 68 0 99 85 4 62 0
61 70 2 71 0 25 70 2 70 0 95 70 1 61 0 80 50 17 71 0
51 30 87 59 10 29 40 8 67 0
test adeno
24 40 2 60 0 18 40 5 69 10 -83 99 3 57 0 31 80 3 39 0
51 60 5 62 0 90 60 22 50 10 52 60 3 43 0 73 60 3 70 0
8 50 5 66 0 36 70 8 61 0 48 10 4 81 0 7 40 4 58 0
140 70 3 63 0 186 90 3 60 0 84 80 4 62 10 19 50 10 42 0
45 40 3 69 0 80 40 4 63 0
test large
52 60 4 45 0 164 70 15 68 10 19 30 4 39 10 53 60 12 66 0
15 30 5 63 0 43 60 11 49 10 340 80 10 64 10 133 75 1 65 0
111 60 5 64 0 231 70 18 67 10 378 80 4 65 0 49 30 3 37 0
;
data Prior;
input _TYPE_ $ Kps Duration Age Prioryes Celladeno Cellsmall
Cellsquamous Therapytest;
datalines;
Mean -0.0320 0 0 0 0 0 0 0
Var 0.00035 1e6 1e6 1e6 1e6 1e6 1e6 1e6
;
run;
ods graphics on;
proc phreg data=VALung;
class Prior(ref='no') Cell(ref='large') Therapy(ref='standard');
model Time*Status(0) = Kps Duration Age Prior Cell Therapy;
bayes seed=1 coeffprior=normal(input=Prior) statistics=(summary interval)
diagnostics=(autocorr ess) plots=trace nmc=1000 nbi=200;
hazardratio 'Hazard Ratio Statement 1' Therapy;
hazardratio 'Hazard Ratio Statement 2' Age / unit=10;
hazardratio 'Hazard Ratio Statement 3' Cell;
run;
