/* STAT-FREQ-014: FREQ — Cochran-Mantel-Haenszel Statistics.
 * Published sample data: SAS/STAT 15.4 User's Guide, Chapter 47, Example 47.7
 * (migraine clinical trial). This is the documented program WITHOUT its
 * PLOTS(ONLY)=RELRISKPLOT(STATS) request, which OpenSAS still rejects loudly
 * (see freq_cmh_relriskplot_gap.sas); it is therefore not the unchanged
 * original. The expected words are the complete SAS listing of the example:
 * stratum odds ratios/relative risks, the three CMH statistics, Mantel-Haenszel
 * and logit common ratios with limits, Breslow-Day, and the TITLE repeated on
 * the summary page. Independent rational checks: src/stat/freq_cmh_tests.zig.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Migraine;
input Gender $ Treatment $ Response $ Count @@;
datalines;
female Active Better 16 female Active Same 11
female Placebo Better 5 female Placebo Same 20
male Active Better 12 male Active Same 16
male Placebo Better 7 male Placebo Same 19
;
ods graphics on;
proc freq data=Migraine;
tables Gender*Treatment*Response /
relrisk cmh noprint;
weight Count;
title 'Clinical Trial for Treatment of Migraine Headaches';
run;
ods graphics off;
run;
quit;
