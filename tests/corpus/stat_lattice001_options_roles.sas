/* expect-rc: 1 (the dropped-response WARNING of cases B/B2, as in
 * stat_lattice001_dropped_response)
 * STAT-LATTICE-001: declarations, roles and options settled by a batched
 * SAS 15.4 reference run of this program (expected listing; the run also
 * held FREQ/WEIGHT steps, now in stat_lattice001_user_errors, and two
 * out-of-format magnitudes, now in stat_lattice001_gaps; the blank line SAS
 * writes before each new page title is dropped). Cases: C COVARIANCE with a
 * repeated basic plan (Rep 1 and 2, Component A rows); A COVARIANCE with
 * three responses (a table per pair after the earlier response, p.5514);
 * B/B2 COVARIANCE with a dropped response (its pairs omitted, p.5516); D
 * Treatment and Treatmnt both present and equal; E a design variable in
 * VAR (NOTE, not analyzed); F3 LABEL and FORMAT have no effect; G1/G2 the
 * adjusted block mean square below the intra-block error (no recovery,
 * Variance of Difference, unadjusted Treatment Means); G3 recovery with
 * efficiency 118.77; H2 negative means; H3 an 11-character response name;
 * I two VAR statements accumulate. Data: the published Getting Started
 * sample of the SAS/STAT 15.4 LATTICE chapter and deterministic transforms.
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
data r; set Pigs(in=a) Pigs(in=b); Rep=1+b; if b then Weight=Weight*1.1 + mod(Treatment*3+Block,5)/10 - Group/20; W2=Weight*2+Treatment/7; run;
title2 'C: cov rep 2'; proc lattice data=r cov; var Weight W2; run;
data w; set Pigs; W3 = Weight + Treatment**2/50 - Block/9; run;
title2 'A: cov three'; proc lattice data=w cov; var Weight W2 W3; run;
data dm; set Pigs; if _n_=5 then W2=.; run;
title2 'B: cov dropped'; proc lattice data=dm cov; var Weight W2; run;
title2 'B2: cov dropped three'; data dm3; set w; if _n_=5 then W2=.; run; proc lattice data=dm3 cov; var Weight W2 W3; run;
data tt; set Pigs; Treatmnt=Treatment; run;
title2 'D: both treatment names'; proc lattice data=tt; var Weight; run;
title2 'E: design var in VAR'; proc lattice data=Pigs; var Group Weight; run;
title2 'F3: label format'; proc lattice data=Pigs; var Weight; label Weight='Weight gain'; format Weight 8.1; run;
data g; set Pigs; Y1 = Treatment + mod(_n_*7,5)/10; Y2 = Treatment + mod(_n_*3,7)/10 + Block/20; Y3 = Weight + (Block=1)*0.01*Group; run;
title2 'G1'; proc lattice data=g; var Y1; run;
title2 'G2'; proc lattice data=g; var Y2; run;
title2 'G3'; proc lattice data=g; var Y3; run;
data h; set Pigs; Neg=Weight-3; Weightgain9=Weight; run;
title2 'H2'; proc lattice data=h; var Neg; run;
title2 'H3'; proc lattice data=h; var Weightgain9; run;
title2 'I: two VAR'; proc lattice data=Pigs; var Weight; var W2; run;
