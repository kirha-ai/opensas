/* STAT-INBREED-001: MATRIXL / INDL (p.5276), a recurring generation number
   (p.5277) and dyadic covariance values, all checked against a SAS 9.4
   reference run (2026-11-28); expected listing copied from that run.
   MATRIXL / INDL show their tables only for generations whose number
   equals the last generation's; other generations print the header and
   "Number of Individuals". A generation number recurring after another
   starts a new generation (E, F of the second "gen = 1" have parents C, D).
   Hand mathematics: rgen G = E x F, f_EF = (f_CC + 2 f_CD + f_DD)/4 =
   (1/2 + 1/2 + 1/2)/4 = 3/8 -> F_G = 3/8, Cov(G,G) = 1.375; covariance 0.875
   between founders A, B gives Cov(A,C) = (1 + 0.875)/2 = 0.9375. Data:
   invented. (The reference run used BY g for the two covariance values;
   here they are separate data sets, so the BY line is left out.) */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
data cv;
input g v;
id='A'; p1=' '; p2=' '; c=.; output;
id='B'; output;
id='C'; p1='A'; p2='B'; c=v; output;
keep g id p1 p2 c;
datalines;
6 0.46875
10 0.875
;
data cv6; set cv; if g=6; run;
data cv10; set cv; if g=10; run;
proc inbreed data=cv6 covar matrix; var id p1 p2 c; run;
proc inbreed data=cv10 covar matrix; var id p1 p2 c; run;
proc inbreed data=cv6 matrix; var id p1 p2 c; run;
proc inbreed data=cv10 matrix; var id p1 p2 c; run;
data gen;
input id $ p1 $ p2 $ gen;
datalines;
A . . 1
B . . 1
C . . 1
D A B 2
E B C 2
F D E 3
G D D 3
;
proc inbreed data=gen covar matrixl; class gen; run;
proc inbreed data=gen covar indl; class gen; run;
proc inbreed data=gen covar matrixl indl; class gen; run;
proc inbreed data=gen covar matrix indl; class gen; run;
proc inbreed data=gen covar ind matrixl; class gen; run;
data rgen;
input id $ p1 $ p2 $ gen;
datalines;
A . . 1
B . . 1
C A B 2
D A B 2
E C D 1
F C D 1
G E F 2
;
proc inbreed data=rgen covar matrix; class gen; run;
proc inbreed data=rgen covar matrixl; class gen; run;
proc inbreed data=rgen covar indl; class gen; run;
