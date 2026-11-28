/* STAT-LATTICE-001: repetition of the entire basic plan through Rep
 * (Input Data Set, p.5515): Rep 1 is the published Getting Started sample of
 * the SAS/STAT 15.4 LATTICE chapter, Rep 2 a deterministic transform of it,
 * so the 3x3 balanced lattice is repeated twice (8 replicates) and Blocks
 * within Replications splits into Component A and Component B (p.5516). The
 * expected listing is a SAS 15.4 reference run of this program (the run also
 * printed three rows of WORK.R before it, omitted here); the blank line SAS
 * writes before each new page title is dropped.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'Q';
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
data r; set Pigs(in=a) Pigs(in=b); Rep=1+b; if b then Weight=Weight*1.1 + mod(Treatment*3+Block,5)/10 - Group/20; run;
title2 'K: rep 2';
proc lattice data=r; run;
