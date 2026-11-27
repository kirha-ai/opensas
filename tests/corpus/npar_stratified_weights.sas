/* SAS Usage Note 25022, public Lehmann fourteen-observation example.
   https://support.sas.com/kb/25/022.html
   Reciprocal stratum weights give centered sum -65/84, variance55/252,
   chi-square2.7435064935064935 and two-sided p=.097650277881934.
   This independently resolves the reciprocal-division typo in S154 p7241.
   Per-stratum (sum,expectation,variance): (1,1.5,.25), (2,2,2/3),
   (3,4,2/3), (8,10.5,5.25). Means/standard errors follow those identities. */
options nodate nonumber;
ods graphics off;
data a;
input blocks treatmnt consump @@;
datalines;
1 1 236 1 2 255
2 1 183 2 2 179 2 2 193
3 1 115 3 1 128 3 2 132
4 1 61 4 1 70 4 1 79 4 2 67 4 2 84 4 2 88
;
run;
proc npar1way data=a;
strata blocks;
class treatmnt;
var consump;
run;
