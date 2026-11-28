/* STAT-LATTICE-002: a simple rectangular lattice (Overview p.5511: k = 3
 * units per block, k(k+1) = 12 treatments, two orthogonal replicates of
 * k+1 blocks; invented data) whose block mean square is below the
 * intra-block error: no recovery, Variance of Difference, LSDs on the RCBD
 * df, unadjusted means under a one-line title. The expected listing is a
 * SAS 15.4 reference run of this program.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'Q5 simple rectangular k=3';
data Rect;
input Group Block Treatment Y @@;
datalines;
1 1 1 10.2 1 1 2 11.5 1 1 3 9.8 1 2 4 12.1 1 2 5 13.0 1 2 6 11.7
1 3 7 8.9 1 3 8 10.4 1 3 9 9.5 1 4 10 12.8 1 4 11 11.1 1 4 12 13.6
2 1 4 11.4 2 1 7 9.9 2 1 10 12.2 2 2 1 10.9 2 2 8 9.7 2 2 11 12.5
2 3 2 12.0 2 3 5 12.4 2 3 12 14.1 2 4 3 9.1 2 4 6 10.8 2 4 9 10.3
;
proc lattice data=Rect; run;
