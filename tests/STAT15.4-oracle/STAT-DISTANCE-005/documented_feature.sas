/* STAT-DISTANCE-005: DISTANCE — Official examples and feature integration regression
 * Source: S154 / Chapter 43 / `Examples: DISTANCE Procedure` (PDF pp. 2770–2782).
 * Discriminates: Example 43.2: Financial Data—Stock Dividends
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Stock Dividends';
data stock;
length Company $ 27;
input Company :$27. Div_1986 Div_1987 Div_1988 Div_1989 Div_1990;
datalines;
Cincinnati_G&E 8.4 8.2 8.4 8.1 8.0
Texas_Utilities 7.9 8.9 10.4 8.9 8.3
Detroit_Edison 9.7 10.7 11.4 7.8 6.5
Orange_&_Rockland_Utilities 6.5 7.2 7.3 7.7 7.9
Kentucky_Utilities 6.5 6.9 7.0 7.2 7.5
Kansas_Power_&_Light 5.9 6.4 6.9 7.4 8.0
Union_Electric 7.1 7.5 8.4 7.8 7.7
Dominion_Resources 6.7 6.9 7.0 7.0 7.4
Allegheny_Power 6.7 7.3 7.8 7.9 8.3
Minnesota_Power_&_Light 5.6 6.1 7.2 7.0 7.5
Iowa-Ill_Gas_&_Electric 7.1 7.5 8.5 7.8 8.0
Pennsylvania_Power_&_Light 7.2 7.6 7.7 7.4 7.1
Oklahoma_Gas_&_Electric 6.1 6.7 7.4 6.7 6.8
Wisconsin_Energy 5.1 5.7 6.0 5.7 5.9
Green_Mountain_Power 7.1 7.4 7.8 7.8 8.3
;
proc distance data=stock method=dcorr out=distdcorr;
var interval(div_1986 div_1987 div_1988 div_1989 div_1990);
id company;
run;
proc print data=distdcorr;
id company;
title2 'Distance Matrix for 15 Utility Stocks';
run;
title2;
ods graphics on;
proc cluster data=distdcorr method=ward pseudo plots(only)=(psf dendrogram);
id company;
run;
proc cluster data=distdcorr method=average pseudo plots(only)=(psf dendrogram);
id company;
run;
