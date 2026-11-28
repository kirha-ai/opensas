/* STAT-LATTICE-002: analysis of variance for partially balanced square
 * lattices (Overview p.5511): Example 75.1 (simple 5x5 soybean lattice,
 * pp.5505-5506, published data), the triple and simple 3x3 lattices formed
 * by groups 1-3, groups 1-2 (Eb < Ee: no recovery) and groups 2 and 4
 * (renumbered; a value printed 0.000200) of the published Getting Started
 * data, and COVARIANCE with a derived second response. The expected listing
 * is a SAS 15.4 reference run of this program (two batched runs); the blank
 * line SAS writes before each new page title is dropped (opensas starts
 * pages without it).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'Q1 soy';
data Soy(drop=plot);
   do Group = 1 to 2; do Block = 1 to 5; do Plot = 1 to 5;
      input Treatment Yield @@; output; end; end; end;
   datalines;
 1 6 2 7 3 5 4 8 5 6 6 16 7 12 8 12 9 13 10 8
11 17 12 7 13 7 14 9 15 14 16 18 17 16 18 13 19 13 20 14
21 14 22 15 23 11 24 14 25 14 1 24 6 13 11 24 16 11 21 8
 2 21 7 11 12 14 17 11 22 23 3 16 8 4 13 12 18 12 23 12
 4 17 9 10 14 30 19 9 24 23 5 15 10 15 15 22 20 16 25 19
;
proc lattice data=Soy; run;
title 'Q2 triple 3x3';
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
proc lattice data=Pigs(where=(group<=3)); var Weight; run;
title 'Q3 simple 3x3 groups 1 and 2';
proc lattice data=Pigs(where=(group<=2)); var Weight; run;
title 'Q4 simple 3x3 groups 2 and 4 renumbered';
data P24; set Pigs; if group in (2,4); if group=4 then group=1; run;
proc lattice data=P24; var Weight; run;
title 'R1 soy cov';
data Soy3; set Soy; Y3 = Yield*0.5 + mod(_n_,3)/7; run;
proc lattice data=Soy3 cov; var Yield Y3; run;
