/* STAT-MIXED-010: MIXED — LSMEANS
 * Source: S154 / Chapter 84 / `LSMEANS Statement` (PDF pp. 6646–6652).
 * Discriminates: Example 84.6: Line-Source Sprinkler Irrigation; explicit statements: LSMEANS
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data line;
length Cult$ 8;
input Block Cult$ @;
row = _n_;
do Sbplt=1 to 12;
if Sbplt le 6 then do;
Irrig = Sbplt;
Dir = 'North';
end;
else do;
Irrig = 13 - Sbplt;
Dir = 'South';
end;
input Y @;
output;
end;
datalines;
1 Luke 2.4 2.7 5.6 7.5 7.9 7.1 6.1 7.3 7.4 6.7 3.8 1.8
1 Nugaines 2.2 2.2 4.3 6.3 7.9 7.1 6.2 5.3 5.3 5.2 5.4 2.9
1 Bridger 2.9 3.2 5.1 6.9 6.1 7.5 5.6 6.5 6.6 5.3 4.1 3.1
2 Nugaines 2.4 2.2 4.0 5.8 6.1 6.2 7.0 6.4 6.7 6.4 3.7 2.2
2 Bridger 2.6 3.1 5.7 6.4 7.7 6.8 6.3 6.2 6.6 6.5 4.2 2.7
2 Luke 2.2 2.7 4.3 6.9 6.8 8.0 6.5 7.3 5.9 6.6 3.0 2.0
3 Nugaines 1.8 1.9 3.7 4.9 5.4 5.1 5.7 5.0 5.6 5.1 4.2 2.2
3 Luke 2.1 2.3 3.7 5.8 6.3 6.3 6.5 5.7 5.8 4.5 2.7 2.3
3 Bridger 2.7 2.8 4.0 5.0 5.2 5.2 5.9 6.1 6.0 4.3 3.1 3.1
;
proc mixed;
class Block Cult Dir Irrig;
model Y = Cult|Dir|Irrig@2;
random Block Block*Dir Block*Irrig;
repeated / type=toep(4) sub=Block*Cult r;
lsmeans Cult|Irrig;
estimate 'Bridger vs Luke' Cult 1 -1 0;
estimate 'Linear Irrig' Irrig -5 -3 -1 1 3 5;
estimate 'B vs L x Linear Irrig' Cult*Irrig
-5 -3 -1 1 3 5 5 3 1 -1 -3 -5;
run;
