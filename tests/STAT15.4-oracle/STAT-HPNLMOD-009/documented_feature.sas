/* STAT-HPNLMOD-009: HPNLMOD — Programming Statements
 * Source: S154 / Chapter 63 / `Programming Statements` (PDF pp. 4887–4889).
 * Discriminates: Getting Started: HPNLMOD Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Enzyme;
input conc rate @@;
datalines;
0.26 124.7 0.30 126.9
0.48 135.9 0.50 137.6
0.54 139.6 0.68 141.1
0.82 142.8 1.14 147.6
1.28 149.8 1.38 149.4
1.80 153.9 2.30 152.5
2.44 154.5 2.48 154.7
;
run;
data remiss;
input remiss cell smear infil li blast temp;
label remiss = 'complete remission';
like = 0;
label like = 'dummy variable for nlin';
datalines;
1 0.8 .83 .66 1.9 1.10 .996
1 0.9 .36 .32 1.4 0.74 .992
0 0.8 .88 .70 0.8 0.176 .982
0 1 .87 .87 0.7 1.053 .986
1 0.9 .75 .68 1.3 0.519 .980
0 1 .65 .65 0.6 0.519 .982

1 0.95 .97 .92 1 1.23 .992
0 0.95 .87 .83 1.9 1.354 1.020
0 1 .45 .45 0.8 0.322 .999
0 0.95 .36 .34 0.5 0 1.038
0 0.85 .39 .33 0.7 0.279 .988
0 0.7 .76 .53 1.2 0.146 .982
0 0.8 .46 .37 0.4 0.38 1.006
0 0.2 .39 .08 0.8 0.114 .990
0 1 .90 .90 1.1 1.037 .990
1 1 .84 .84 1.9 2.064 1.020
0 0.65 .42 .27 0.5 0.114 1.014
0 1 .75 .75 1 1.322 1.004
0 0.5 .44 .22 0.6 0.114 .990
1 1 .63 .63 1.1 1.072 .986
0 1 .33 .33 0.4 0.176 1.010
0 0.9 .93 .84 0.6 1.591 1.020
1 1 .58 .58 1 0.531 1.002
0 0.95 .32 .30 1.6 0.886 .988
1 1 .60 .60 1.7 0.964 .990
1 1 .69 .69 0.9 0.398 .986
0 1 .73 .73 0.7 0.398 .986
;
run;
proc hpnlmod data=enzyme;
parms theta1=160 theta2=0.1;
model rate ~ residual(theta1*conc / (theta2 + conc));
run;
proc hpnlmod data=remiss corr;
parms int=-10 a=-2 b=-1 c=6;
linp = int + a*cell + b*li + c*temp;
p = probnorm(linp);
model remiss ~ binary(1-p);
run;
