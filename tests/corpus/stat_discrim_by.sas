/* expect-rc: 1
 * STAT-DISCRIM-001: default PROC DISCRIM (two identical BY groups) on the published SASHELP.FISH data
 * (one observation with a missing VAR value is excluded): counts, class
 * levels with equal priors, pooled covariance log determinant, pairwise
 * generalized squared distances, linear discriminant function and the
 * resubstitution summary with error count estimates. Expected listing is
 * the SAS 9.4 reference output of this program, minus the blank line SAS
 * writes at the top of each page (opensas page convention).
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Fish Measurement Data';
data _oracle_input; set sashelp.fish; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc discrim data=_oracle_input;
by _oracle_by;
class Species;
run;
