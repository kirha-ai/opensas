/* STAT-PHREG-011: PHREG — Proportional Rates/Means Models for Recurrent Events / Analysis of Multivariate Failure Time Data
 * Source: S154 / Chapter 92 / `Proportional Rates/Means Models for Recurrent Events` (PDF pp. 7400–7401); S154 / Chapter 92 / `Analysis of Multivariate Failure Time Data` (PDF pp. 7419–7428).
 * Discriminates: Example 92.10: Analysis of Recurrent Events Data
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Bladder;
keep ID TStart TStop Status Trt Number Size Visit;
retain ID TStart 0;
array tt[4] T1-T4;
infile datalines missover;
input Trt Time Number Size T1-T4;
ID + 1;
TStart=0;
do Visit=1 to 4;
if tt[Visit] = . then do;
TStop=Time;
Status=0;
end;
else do;
TStop=tt[Visit];
Status=1;
end;
output;
TStart=TStop;
end;
if (TStart < Time) then delete;
datalines;
1 0 1 1
1 1 1 3
1 4 2 1
1 7 1 1
1 10 5 1
1 10 4 1 6
1 14 1 1
1 18 1 1
1 18 1 3 5
1 18 1 1 12 16
1 23 3 3
1 23 1 3 10 15
1 23 1 1 3 16 23
1 23 3 1 3 9 21
1 24 2 3 7 10 16 24
1 25 1 1 3 15 25
1 26 1 2
1 26 8 1 1
1 26 1 4 2 26
1 28 1 2 25
1 29 1 4
1 29 1 2
1 29 4 1
1 30 1 6 28 30
1 30 1 5 2 17 22
1 30 2 1 3 6 8 12
1 31 1 3 12 15 24
1 32 1 2
1 34 2 1
1 36 2 1
1 36 3 1 29
1 37 1 2
1 40 4 1 9 17 22 24
1 40 5 1 16 19 23 29
1 41 1 2
1 43 1 1 3
1 43 2 6 6
1 44 2 1 3 6 9
1 45 1 1 9 11 20 26
1 48 1 1 18
1 49 1 3
1 51 3 1 35
1 53 1 7 17
1 53 3 1 3 15 46 51
1 59 1 1
1 61 3 2 2 15 24 30
1 64 1 3 5 14 19 27
1 64 2 3 2 8 12 13
2 1 1 3
2 1 1 1
2 5 8 1 5
2 9 1 2
2 10 1 1
2 13 1 1
2 14 2 6 3
2 17 5 3 1 3 5 7
2 18 5 1
2 18 1 3 17
2 19 5 1 2
2 21 1 1 17 19
2 22 1 1
2 25 1 3
2 25 1 5
2 25 1 1
2 26 1 1 6 12 13
2 27 1 1 6
2 29 2 1 2
2 36 8 3 26 35
2 38 1 1
2 39 1 1 22 23 27 32
2 39 6 1 4 16 23 27
2 40 3 1 24 26 29 40
2 41 3 2
2 41 1 1
2 43 1 1 1 27
2 44 1 1
2 44 6 1 2 20 23 27
2 45 1 2
2 46 1 4 2
2 46 1 4
2 49 3 3
2 50 1 1
2 50 4 1 4 24 47
2 54 3 4
2 54 2 1 38
2 59 1 3
;
title 'Intensity Model and Proportional Means Model';
proc phreg data=Bladder covm covs(aggregate);
model (TStart, TStop) * Status(0) = Trt Number Size;
id id;
where TStart < TStop;
run;
data Bladder2(drop=LastStatus);
retain LastStatus;
set Bladder;
by ID;
if first.id then LastStatus=1;
if (Status=0 and LastStatus=0) then delete;
LastStatus=Status;
Gaptime=Tstop-Tstart;
run;
title 'PWP Total Time Model with Noncommon Effects';
proc phreg data=Bladder2;
model (TStart,Tstop) * Status(0) = Trt1-Trt4 Number1-Number4
Size1-Size4;
Trt1= Trt * (Visit=1);
Trt2= Trt * (Visit=2);
Trt3= Trt * (Visit=3);
Trt4= Trt * (Visit=4);
Number1= Number * (Visit=1);
Number2= Number * (Visit=2);
Number3= Number * (Visit=3);
Number4= Number * (Visit=4);
Size1= Size * (Visit=1);
Size2= Size * (Visit=2);
Size3= Size * (Visit=3);
Size4= Size * (Visit=4);
strata Visit;
run;
title 'PWP Gap-Time Model with Noncommon Effects';
proc phreg data=Bladder2;
model Gaptime * Status(0) = Trt1-Trt4 Number1-Number4
Size1-Size4;
Trt1= Trt * (Visit=1);
Trt2= Trt * (Visit=2);
Trt3= Trt * (Visit=3);
Trt4= Trt * (Visit=4);
Number1= Number * (Visit=1);
Number2= Number * (Visit=2);
Number3= Number * (Visit=3);
Number4= Number * (Visit=4);
Size1= Size * (Visit=1);
Size2= Size * (Visit=2);
Size3= Size * (Visit=3);
Size4= Size * (Visit=4);
strata Visit;
run;
title2 'PWP Total Time Model with Common Effects';
proc phreg data=Bladder2;
model (tstart,tstop) * status(0) = Trt Number Size;
strata Visit;
run;
title2 'PWP Gap Time Model with Common Effects';
proc phreg data=Bladder2;
model Gaptime * Status(0) = Trt Number Size;
strata Visit;
run;
title 'Wei-Lin-Weissfeld Model';
proc phreg data=Bladder covs(aggregate);
model TStop*Status(0)=Trt1-Trt4 Number1-Number4 Size1-Size4;
Trt1= Trt * (Visit=1);
Trt2= Trt * (Visit=2);
Trt3= Trt * (Visit=3);
Trt4= Trt * (Visit=4);
Number1= Number * (Visit=1);
Number2= Number * (Visit=2);
Number3= Number * (Visit=3);
Number4= Number * (Visit=4);
Size1= Size * (Visit=1);
Size2= Size * (Visit=2);
Size3= Size * (Visit=3);
Size4= Size * (Visit=4);
strata Visit;
id ID;
TREATMENT: test trt1,trt2,trt3,trt4/average e;
run;
