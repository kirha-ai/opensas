/* STAT-FREQ-014: hand-calculated CMH with degenerate strata (invented data).
 * Strata 1 and 2 are the same 3x2 table T=[[3,1],[1,3],[3,1]] (n=12, rows
 * 4/4/4, columns 7/5). One stratum: Pearson=96/35, general association
 * (n-1)/n*Pearson=88/35; identical strata double G and Var(G), so
 * Q_G = 176/35 = 5.0286 with df=(3-1)(2-1)=2 and p=exp(-88/35)=0.0809.
 * With two columns the row mean score statistic equals Q_G (df=R-1=2).
 * Table scores 1,2,3 are uncorrelated with the response in T
 * ((-1)(-2/3)+(1)(-2/3)=0), so the correlation statistic is 0, p=1, df=1.
 * Stratum 3 has one observation (n-1=0) and stratum 4 has an empty column
 * (zero expected-value variance): neither changes any statistic, but both
 * count in the total sample size 12+12+1+6=31.
 */
options nosyntaxcheck; ods graphics off;
data t; input s r c n @@; datalines;
1 1 1 3 1 1 2 1 1 2 1 1 1 2 2 3 1 3 1 3 1 3 2 1
2 1 1 3 2 1 2 1 2 2 1 1 2 2 2 3 2 3 1 3 2 3 2 1
3 2 2 1
4 1 1 2 4 2 1 1 4 3 1 3
;
proc freq data=t; tables s*r*c / cmh noprint; weight n; run;
