/* STAT-MI-015: MI — Plot Options Superseded by ODS Graphics / ODS Graphics
 * Source: S154 / Chapter 82 / `Plot Options Superseded by ODS Graphics` (PDF pp. 6493–6498); S154 / Chapter 82 / `ODS Graphics` (PDF pp. 6499–6500).
 * Discriminates: Example 82.8: FCS Method with Trace Plot
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
data Fish3;
title 'Fish Measurement Data';
input Species $ Length Width @@;
datalines;
Roach 16.2 2.2680 Roach 20.3 2.8217 Roach 21.2 .
Roach . 3.1746 Roach 22.2 3.5742 Roach 22.8 3.3516
Roach 23.1 3.3957 . 23.7 . Roach 24.7 3.7544
Roach 24.3 3.5478 Roach 25.3 . Roach 25.0 3.3250
Roach 25.0 3.8000 Roach 27.2 3.8352 Roach 26.7 3.6312
Roach 26.8 4.1272 Roach 27.9 3.9060 Roach 29.2 4.4968
Roach 30.6 4.7736 Roach 35.0 5.3550 Parkki 16.5 2.3265
Parkki 17.4 . Parkki 19.8 2.6730 Parkki 21.3 2.9181
Parkki 22.4 3.2928 Parkki 23.2 3.2944 Parkki 23.2 3.4104
Parkki 24.1 3.1571 . . 3.6636 Parkki 28.0 4.1440
Parkki 29.0 4.2340 Perch 8.8 1.4080 . 14.7 1.9992
Perch 16.0 2.4320 Perch 17.2 2.6316 Perch 18.5 2.9415
Perch 19.2 3.3216 . 19.4 3.1234 Perch 20.2 .
Perch 20.8 3.0368 Perch 21.0 2.7720 Perch 22.5 3.5550
Perch 22.5 3.3075 Perch 22.5 3.6675 Perch . 3.5340
Perch 23.5 3.4075 Perch 23.5 3.5250 Perch 23.5 3.5250
. 23.5 3.5250 Perch 23.5 3.9950 Perch 24.0 3.6240
Perch 24.0 3.6240 Perch 24.2 3.6300 Perch 24.5 3.6260
Perch 25.0 3.7250 Perch . 3.7230 Perch 25.5 3.8250
Perch . 4.1658 Perch 26.5 3.6835 . 27.0 4.2390
Perch . 4.1440 Perch 28.7 5.1373 . 28.9 4.3350
Perch 28.9 4.3350 Perch 28.9 4.5662 Perch 29.4 4.2042
Perch 30.1 4.6354 Perch 31.6 4.7716 Perch 34.0 6.0180
Perch 36.5 6.3875 Perch 37.3 7.7957 Perch 39.0 .
Perch 38.3 6.7408 Perch . 6.2646 . 39.3 .
Perch 41.4 7.4934 Perch 41.4 6.0030 Perch 41.3 7.3514
Perch 42.3 7.1064 Perch 42.5 7.2250 Perch 42.4 7.4624
Perch 42.5 6.6300 Perch 44.6 6.8684 Perch 45.2 7.2772
Perch 45.5 7.4165 Perch 46.0 8.1420 . 46.6 7.5958
;
run;
ods graphics on;
proc mi data=Fish3 seed=1305417 nimpute=5 out=outex8;
class Species;
fcs plots=trace
logistic(Species= Length Width Length*Width /details link=glogit);
var Species Length Width;
run;
proc print data=outex8(obs=10);
title 'First 10 Observations of the Imputed Data Set';
run;
ods trace off;
ods trace off;
ods graphics off;
