/* STAT-GLIMMIX-018: GLIMMIX — The Likelihood Ratio Test / Wald Versus Likelihood Ratio Tests / Confidence Bounds Based on Likelihoods / One- and Two-Sided Testing, Mixture Distributions / Handling the Degenerate Distribution
 * Source: S154 / Chapter 52 / `The Likelihood Ratio Test` (PDF pp. 3848–3849); S154 / Chapter 52 / `Wald Versus Likelihood Ratio Tests` (PDF p. 3851); S154 / Chapter 52 / `Confidence Bounds Based on Likelihoods` (PDF pp. 3851–3855); S154 / Chapter 52 / `One- and Two-Sided Testing, Mixture Distributions` (PDF pp. 3849–3851); S154 / Chapter 52 / `Handling the Degenerate Distribution` (PDF p. 3851).
 * Discriminates: Example 52.4: Quasi-likelihood Estimation for Proportions with Unknown Distribution
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data blotch;
array p{9} pct1-pct9;
input variety pct1-pct9;
do site = 1 to 9;
prop = p{site}/100;
output;
end;
drop pct1-pct9;
datalines;
1 0.05 0.00 1.25 2.50 5.50 1.00 5.00 5.00 17.50
2 0.00 0.05 1.25 0.50 1.00 5.00 0.10 10.00 25.00
3 0.00 0.05 2.50 0.01 6.00 5.00 5.00 5.00 42.50
4 0.10 0.30 16.60 3.00 1.10 5.00 5.00 5.00 50.00
5 0.25 0.75 2.50 2.50 2.50 5.00 50.00 25.00 37.50
6 0.05 0.30 2.50 0.01 8.00 5.00 10.00 75.00 95.00
7 0.50 3.00 0.00 25.00 16.50 10.00 50.00 50.00 62.50
8 1.30 7.50 20.00 55.00 29.50 5.00 25.00 75.00 95.00
9 1.50 1.00 37.50 5.00 20.00 50.00 50.00 75.00 95.00
10 1.50 12.70 26.25 40.00 43.50 75.00 75.00 75.00 95.00
;
proc glimmix data=blotch;
class site variety;
model prop = site variety / link=logit dist=binomial;
random _residual_;
lsmeans variety / diff=control('1');
run;
ods graphics on;
ods select PearsonPanel;
proc glimmix data=blotch plots=pearsonpanel;
class site variety;
model prop = site variety / link=logit dist=binomial;
random _residual_;
run;
ods graphics off;
ods graphics on;
ods select ModelInfo FitStatistics LSMeans Diffs PearsonPanel;
proc glimmix data=blotch plots=pearsonpanel;
class site variety;
_variance_ = _mu_**2 * (1-_mu_)**2;
model prop = site variety / link=logit;
lsmeans variety / diff=control('1');
run;
ods graphics off;
run;
quit;
