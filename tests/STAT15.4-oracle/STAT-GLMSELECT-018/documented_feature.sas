/* STAT-GLMSELECT-018: GLMSELECT — PERFORMANCE
 * Source: S154 / Chapter 56 / `PERFORMANCE Statement` (PDF p. 4355).
 * Discriminates: Example 56.2: Using Validation and Cross Validation; explicit statements: PERFORMANCE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data analysisData testData;
drop i j c3Num;
length c3 $ 7;
array x{20} x1-x20;
do i=1 to 1500;
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
y = 10 + x1 + 2*x5 + 3*x10 + 4*x20 + 3 *x1*x7 + 8*x6*x7
+ 5*(c1=3)*c3Num + 8*(c1=7) + 5 *rannor(1);
if ranuni(1) < 2/3 then output analysisData;
else output testData;
end;
run;
ods graphics on;
proc glmselect data=analysisData testdata=testData
seed=1 plots(stepAxis=number)=(criterionPanel ASEPlot);
partition fraction(validate=0.5);
class c1 c2 c3(order=data);
model y = c1|c2|c3|x1|x2|x3|x4|x5|x5|x6|x7|x8|x9|x10
|x11|x12|x13|x14|x15|x16|x17|x18|x19|x20 @2
/ selection=stepwise(choose = validate
select = sl)
hierarchy=single stb;
run;
proc glmselect data=analysisData testdata=testData
seed=1 plots(stepAxis=number)=all;
partition fraction(validate=0.5);
class c1(split) c2 c3(order=data);
model y = c1|c2|c3|x1|x2|x3|x4|x5|x5|x6|x7|x8|x9|x10
|x11|x12|x13|x14|x15|x16|x17|x18|x19|x20 @2
/ selection=stepwise(stop = validate
select = sl)
hierarchy=single;
output out=outData;
run;
proc print data=outData(obs=5);
run;
proc glmselect data=analysisData testdata=testData
plots(stepAxis=number)=(criterionPanel ASEPlot) seed=314159;
class c1(split) c2 c3(order=data);
model y = c1|c2|c3|x1|x2|x3|x4|x5|x5|x6|x7|x8|x9|x10
|x11|x12|x13|x14|x15|x16|x17|x18|x19|x20 @2
/ selection = stepwise(choose = cv
select = sl)
stats = press
cvMethod = split(5)
cvDetails = all
hierarchy = single;
output out=outData;
run;
proc print data=outData(obs=8);
run;
proc glmselect data=analysisData testdata=testData plots=ASEPlot seed=314159;
class c1 c2 c3(order=data);
model y = c1|c2|c3|x1|x2|x3|x4|x5|x5|x6|x7|x8|x9|x10
|x11|x12|x13|x14|x15|x16|x17|x18|x19|x20 @2
/ selection=forward(stop=none)
hierarchy=single;
performance buildSSCP = full;
run;
ods graphics off;
run;
quit;
