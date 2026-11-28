/* STAT-LATTICE-001: conflicting and repeated declarations settled by a
 * batched SAS 15.4 reference run of this program (expected listing; the run
 * also held error cases, now in stat_lattice001_user_errors and
 * stat_lattice001_gaps; the blank line SAS writes before each new page
 * title is dropped). Cases: P adjusted block mean square above the
 * intra-block error but efficiency 103.88 (no adjustment: Variance of
 * Difference 2 Ee / r, Treatment Means); Q1 Treatment and Treatmnt both
 * present and different (Treatmnt is read); Q3 a variable repeated across
 * VAR statements and Q10 within one VAR statement (analyzed again); Q4
 * ATTRIB has no effect. Data: the published Getting Started sample of the
 * SAS/STAT 15.4 LATTICE chapter and deterministic transforms.
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
data g; set Pigs; Y4 = Treatment + mod(_n_*7,5)/10 + 0.08*(Block=1)*Group; run;
title2 'P: Eb>Ee eff<=105'; proc lattice data=g; var Y4; run;
data tt; set Pigs; Treatmnt=Treatment; if Group=1 and Block=1 then Treatmnt=4-Treatment; run;
title2 'Q1: treatment and treatmnt differ'; proc lattice data=tt; var Weight; run;
title2 'Q3: var repeated across'; proc lattice data=Pigs; var Weight; var Weight W2; run;
title2 'Q4: attrib'; proc lattice data=Pigs; var Weight; attrib Weight label='x' format=8.1; run;
title2 'Q10: var repeated within'; proc lattice data=Pigs; var Weight Weight; run;
