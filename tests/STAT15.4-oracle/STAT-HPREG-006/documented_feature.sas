/* STAT-HPREG-006: HPREG — PARTITION / SELECTION / Criteria Used in Model Selection
 * Source: S154 / Chapter 67 / `PARTITION Statement` (PDF p. 5035); S154 / Chapter 67 / `SELECTION Statement` (PDF pp. 5036–5038); S154 / Chapter 67 / `Criteria Used in Model Selection` (PDF pp. 5038–5040).
 * Discriminates: Example 67.1: Model Selection with Validation; explicit statements: PARTITION, SELECTION
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data analysisData;
drop i j c3Num;
length c3$ 7;
array x{20} x1-x20;
do i=1 to 15000;
do j=1 to 20;
x{j} = ranuni(1);
end;
c1 = 1 + mod(i,8);
c2 = ranbin(1,3,.6);
if i < 50 then do;
c3 = 'tiny';
c3Num=1;
end;
else if i < 250 then do;
c3 = 'small';
c3Num=1;
end;
else if i < 600 then do;
c3 = 'average';
c3Num=2;
end;
else if i < 1200 then do;
c3 = 'big';
c3Num=3;
end;
else do;
c3 = 'huge';
c3Num=5;
end;
yTrue = 10 + x1 + 2*x5 + 3*x10 + 4*x20 + 3 *x1*x7 + 8*x6*x7
+ 5*(c1=3)*c3Num + 8*(c1=7);
error = 5*rannor(1);
y = yTrue + error;
if mod(i,3)=1 then Role = 'TRAIN';
else if mod(i,3)=2 then Role = 'VAL';
else Role = 'TEST';
output;
end;
run;
proc summary data=analysisData;
class role;
ways 1;
var error;
output out=ASE uss=uss n=n;
data ASE;
set ASE;
OracleASE = uss / n;
label OracleASE = 'Oracle ASE';
keep Role OracleASE;
proc print data=ASE label noobs;
run;
proc print data=ASE label noobs;
run;
proc hpreg data=analysisData;
partition roleVar=role(train='TRAIN' validate='VAL' test='TEST');
class c1 c2 c3(order=data);
model y = c1|c2|c3|x1|x2|x3|x4|x5|x5|x6|x7|x8|x9|x10
|x11|x12|x13|x14|x15|x16|x17|x18|x19|x20 @2 /stb;
selection method = stepwise(select=sl sle=0.1 sls=0.15 choose=validate)
hierarchy=single details=steps;
run;
proc hpreg data=analysisData;
partition roleVar=role(train='TRAIN' validate='VAL' test='TEST');
class c1(split) c2 c3(order=data);
model y = c1|c2|c3|x1|x2|x3|x4|x5|x5|x6|x7|x8|x9|x10
|x11|x12|x13|x14|x15|x16|x17|x18|x19|x20 @2 /stb;
selection method = stepwise(select=sl sle=0.1 sls=0.15 choose=validate)
hierarchy=single details=steps;
run;
