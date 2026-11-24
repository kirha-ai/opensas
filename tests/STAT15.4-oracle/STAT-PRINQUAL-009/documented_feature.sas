/* STAT-PRINQUAL-009: PRINQUAL — ODS Graphics
 * Source: S154 / Chapter 99 / `ODS Graphics` (PDF pp. 8072–8073).
 * Discriminates: Example 99.2: Principal Components of Basketball Rankings
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods graphics on;
ods trace on;
ods trace on;
data bballm;
input School :$13. CSN DurhamSun DurhamHerald WashingtonPost
USA_Today SportMagazine InsideSports UPI AP SportsIllustrated;
label CSN = 'Community Sports News (Chapel Hill, NC)'
DurhamSun = 'Durham Sun'
DurhamHerald = 'Durham Morning Herald'
WashingtonPost = 'Washington Post'
USA_Today = 'USA Today'
SportMagazine = 'Sport Magazine'
InsideSports = 'Inside Sports'
UPI = 'United Press International'
AP = 'Associated Press'
SportsIllustrated = 'Sports Illustrated'
;
format CSN--SportsIllustrated 5.1;
datalines;
Louisville 1 8 1 9 8 9 6 10 9 9
Georgia_Tech 2 2 4 3 1 1 1 2 1 1
Kansas 3 4 5 1 5 11 8 4 5 7
Michigan 4 5 9 4 2 5 3 1 3 2
Duke 5 6 7 5 4 10 4 5 6 5
UNC 6 1 2 2 3 4 2 3 2 3
Syracuse 7 10 6 11 6 6 5 6 4 10
Notre_Dame 8 14 15 13 11 20 18 13 12 .
Kentucky 9 15 16 14 14 19 11 12 11 13
LSU 10 9 13 . 13 15 16 9 14 8
DePaul 11 . 21 15 20 . 19 . . 19
Georgetown 12 7 8 6 9 2 9 8 8 4
Navy 13 20 23 10 18 13 15 . 20 .
Illinois 14 3 3 7 7 3 10 7 7 6
Iowa 15 16 . . 23 . . 14 . 20
Arkansas 16 . . . 25 . . . . 16
Memphis_State 17 . 11 . 16 8 20 . 15 12
Washington 18 . . . . . . 17 . .
UAB 19 13 10 . 12 17 . 16 16 15
UNLV 20 18 18 19 22 . 14 18 18 .
NC_State 21 17 14 16 15 . 12 15 17 18
Maryland 22 . . . 19 . . . 19 14
Pittsburgh 23 . . . . . . . . .
Oklahoma 24 19 17 17 17 12 17 . 13 17
Indiana 25 12 20 18 21 . . . . .
Virginia 26 . 22 . . 18 . . . .
Old_Dominion 27 . . . . . . . . .
Auburn 28 11 12 8 10 7 7 11 10 11
St._Johns 29 . . . . 14 . . . .
UCLA 30 . . . . . . 19 . .
St._Joseph's . . 19 . . . . . . .
Tennessee . . 24 . . 16 . . . .
Montana . . . 20 . . . . . .
Houston . . . . 24 . . . . .
Virginia_Tech . . . . . . 13 . . .
;
* Find maximum rank for each news service and replace
* each missing value with the next highest rank.;
proc means data=bballm noprint;
output out=maxrank
max=mcsn mdurs mdurh mwas musa mspom mins mupi map mspoi;
run;
data bball;
set bballm;
if _n_=1 then set maxrank;
array services[10] CSN--SportsIllustrated;
array maxranks[10] mcsn--mspoi;
keep School CSN--SportsIllustrated;
do i=1 to 10;
if services[i]=. then services[i]=maxranks[i]+1;
end;
run;
* Assume that the ranks are ordinal and that unranked teams would have
* been ranked lower than ranked teams. Monotonically transform all ranked
* teams while estimating the unranked teams. Enforce the constraint that
* the missing ranks are estimated to be less than the observed ranks.
* Order the unranked teams optimally within this constraint. Do this so
* as to maximize the variance accounted for by one linear combination.
* This makes the data as nearly rank one as possible, given the constraints.
*
* NOTE: The UNTIE transformation should be used with caution.
* It frequently produces degenerate results.;
ods graphics on;
proc prinqual data=bball out=tbball scores n=1 tstandard=z
plots=transformations;
title2 'Optimal Monotonic Transformation of Ranked Teams';
title3 'with Constrained Estimation of Unranked Teams';
transform untie(CSN -- SportsIllustrated);
id School;
run;
* Perform the Final Principal Component Analysis;
proc factor nfactors=1 plots=scree;
title4 'Principal Component Analysis';
ods select factorpattern screeplot;
var TCSN -- TSportsIllustrated;
run;
proc sort;
by Prin1;
run;
* Display Scores on the First Principal Component;
proc print;
title4 'Teams Ordered by Scores on First Principal Component';
var School Prin1;
run;
ods trace off;
ods trace off;
ods graphics off;
