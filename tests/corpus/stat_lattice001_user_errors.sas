/* expect-rc: 1
 * STAT-LATTICE-001: documented invalid input is a user error with no
 * listing: a missing Group value stops the analysis (p.5516; message text of
 * a SAS 15.4 reference run), Block is a required design variable (p.5515),
 * VAR variables must be numeric, a VAR variable may not repeat, and an empty
 * input data set (SAS 15.4 stops with an internal exception). Published
 * Getting Started sample data.
 */
options nosyntaxcheck;
data Pigs;
input Group Block Treatment Weight @@;
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
data f; set Pigs; if _n_=3 then Group=.; run;
proc lattice data=f; run;
data nb; set Pigs; drop Block; run;
proc lattice data=nb; run;
data c; set Pigs; length s $ 2; s='a'; run;
proc lattice data=c; var s; run;
proc lattice data=Pigs; var Weight Weight; run;
data e; set Pigs; stop; run;
proc lattice data=e; run;
