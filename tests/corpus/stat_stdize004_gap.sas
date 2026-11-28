/* expect-rc: 2
 * STAT-STDIZE-004: valid PROC STDIZE requests that stay loud D-009 gaps:
 * PCTLMTD=ONEPASS / P2 (the one-pass estimator modifies the P2 algorithm in
 * ways the guide does not specify: real SAS gives 8 / 58.2222 for METHOD=IQR
 * NMARKERS=7 on ten values where order statistics give 17 / 50) and
 * PCTLDEF= with the default INITIAL=MAD of an A-estimate (not verified).
 * Nothing is printed for these steps. Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=120;
data a;
input x @@;
datalines;
2 3 5 8 13 21 34 55 89 144
;
proc stdize data=a method=iqr pctlmtd=onepass nmarkers=7 pstat; var x; run;
proc stdize data=a method=median pctlmtd=p2 pstat; var x; run;
proc stdize data=a method=abw(4) pctldef=1 pstat; var x; run;
