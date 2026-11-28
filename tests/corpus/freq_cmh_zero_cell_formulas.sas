/* STAT-FREQ-014: stratified 2x2 formulas with a zero cell (invented data).
 * Strata [[3,0],[1,3]] (n=7) and [[2,1],[1,2]] (n=6). Expected values were
 * derived from the SAS/STAT 15.4 formulas independently of OpenSAS:
 *   CMH: G=9/7+1/2=25/14, Var=24/49+9/20=921/980, Q=3125/921=3.3931,
 *        df=1, p=erfc(sqrt(Q/2))=0.0655 (all three statistics for 2x2).
 *   Mantel-Fleiss: sum m=45/14, lower sums 0, upper sums 6,
 *        min(45/14, 39/14)=39/14=2.7857 (<5, warning).
 *   OR_MH=(9/7+4/6)/(1/6)=82/7=11.7143; Robins-Breslow-Greenland limits
 *        0.7341, 186.9295. RR_MH column 1 = 38/13=2.9231 (0.8678, 9.8462);
 *        column 2 = 7/32=0.2188 (0.0306, 1.5643), Greenland-Robins variance.
 *   Logit: the zero cell adds 0.5 to every cell of stratum 1 for the odds
 *        ratio and the column 2 risk (n12=0), not for column 1:
 *        OR 7.8688 (0.6819, 90.8072); RR1 2.8805 (0.8408, 9.8687);
 *        RR2 0.3625 (0.0822, 1.5987).
 *   Breslow-Day at OR_MH: fitted n11 solves the cross-product quadratic,
 *        variance is the inverse sum of reciprocal fitted cells:
 *        Q_BD=1.0480, df=2-1=1, p=0.3060.
 */
options nosyntaxcheck; ods graphics off;
data m; input s r c n @@; datalines;
1 1 1 3 1 1 2 0 1 2 1 1 1 2 2 3
2 1 1 2 2 1 2 1 2 2 1 1 2 2 2 2
;
proc freq data=m; tables s*r*c / cmh(mf) noprint; weight n; run;
