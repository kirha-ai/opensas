/* expect-rc: 1
 * STAT-LATTICE-001: Missing Values (p.5516): a response variable with a
 * missing value is dropped with a warning while the others are analyzed;
 * when every response is dropped nothing is listed. Published Getting
 * Started sample data (W2 derived). The expected listing and the warning
 * text are a SAS 15.4 reference run of this program.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'Q';
data Pigs;
input Group Block Treatment Weight @@;
W2 = Weight*2 + Treatment/7;
datalines;
1 1 1 2.20 1 1 2 1.84 1 1 3 2.18 1 2 4 2.05 1 2 5 0.85
1 2 6 1.86 1 3 7 0.73 1 3 8 1.60 1 3 9 1.76
2 1 1 1.19 2 1 4 1.20 2 1 7 1.15 2 2 2 2.26 2 2 5 1.07
2 2 8 1.45 2 3 3 2.12 2 3 6 2.03 2 3 9 1.63
3 1 1 1.81 3 1 5 1.16 3 1 9 1.11 3 2 2 1.76 3 2 6 2.16
3 2 7 1.80 3 3 3 1.71 3 3 4 1.57 3 3 8 1.13
4 1 1 1.77 4 1 6 1.57 4 1 8 1.43 4 2 2 1.50 4 2 4 1.60
4 2 9 1.42 4 3 3 2.04 4 3 5 0.93 4 3 7 1.78
;
title2 'C: one response missing';
data m; set Pigs; if _n_=3 then W2=.; run;
proc lattice data=m; run;
title2 'D: all missing';
data m2; set Pigs; if _n_=3 then do; W2=.; Weight=.; end; run;
proc lattice data=m2; run;
