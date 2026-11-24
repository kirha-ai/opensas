/* STAT-LOGISTIC-019: LOGISTIC — Scoring Data Sets
 * Source: S154 / Chapter 79 / `Scoring Data Sets` (PDF pp. 5941–5946).
 * Discriminates: Example 79.16: Scoring Data Sets
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Crops;
length Crop $ 10;
infile datalines truncover;
input Crop $ @@;
do i=1 to 3;
input x1-x4 @@;
if (x1 ^= .) then output;
end;
input;
datalines;
Corn       16 27 31 33 15 23 30 30 16 27 27 26
Corn       18 20 25 23 15 15 31 32 15 32 32 15
Corn       12 15 16 73
Soybeans   20 23 23 25 24 24 25 32 21 25 23 24
Soybeans   27 45 24 12 12 13 15 42 22 32 31 43
Cotton     31 32 33 34 29 24 26 28 34 32 28 45
Cotton     26 25 23 24 53 48 75 26 34 35 25 78
Sugarbeets 22 23 25 42 25 25 24 26 34 25 16 52
Sugarbeets 54 23 21 54 25 43 32 15 26 54 2 54
Clover     12 45 32 54 24 58 25 34 87 54 61 21
Clover     51 31 31 16 96 48 54 62 31 31 11 11
Clover     56 13 13 71 32 13 27 32 36 26 54 32
Clover     53 08 06 54 32 32 62 16
;
ods graphics on;
proc logistic data=Crops;
model Crop=x1-x4 / link=glogit;
score out=Score1;
effectplot slicefit(x=x3);
run;
proc logistic data=Crops outmodel=work.CropModel;
model Crop=x1-x4 / link=glogit;
score data=Crops out=Score2;
store CropModel2;
run;
proc logistic inmodel=work.CropModel;
score data=Crops out=Score3;
run;
proc plm source=CropModel2;
score data=Crops out=ScorePLM predicted=p / ilink;
run;
proc transpose data=ScorePLM out=Score4 prefix=P_ let;
id _LEVEL_;
var p;
by x1-x4 notsorted;
run;
data Score4(drop=_NAME_ _LABEL_);
merge Score4 Crops(keep=Crop x1-x4);
F_Crop=Crop;
run;
proc summary data=ScorePLM nway;
by x1-x4 notsorted;
var p;
output out=into maxid(p(_LEVEL_))=I_Crop;
run;
data Score4;
merge Score4 into(keep=I_Crop);
run;
data Prior;
length Crop $10.;
input Crop _PRIOR_;
datalines;
Clover     11
Corn       7
Cotton     6
Soybeans   6
Sugarbeets 6
;
proc logistic inmodel=work.CropModel;
score data=Crops prior=prior out=Score5 fitstat;
run;
proc freq data=Score1;
table F_Crop*I_Crop / nocol nocum nopercent;
run;
data Test;
input Crop $ 1-10 x1-x4;
datalines;
Corn       16 27 31 33
Soybeans   21 25 23 24
Cotton     29 24 26 28
Sugarbeets 54 23 21 54
Clover     32 32 62 16
;
proc logistic noprint inmodel=work.CropModel;
score data=Test out=ScoredTest;
run;
proc print data=ScoredTest label noobs;
var F_Crop I_Crop P_Clover P_Corn P_Cotton P_Soybeans P_Sugarbeets;
run;
run;
quit;
