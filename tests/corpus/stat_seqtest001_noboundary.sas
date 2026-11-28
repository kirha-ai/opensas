/* expect-rc: 1
   STAT-SEQTEST-001: the BOUNDARY= option is required in the PROC SEQTEST
   statement (SAS/STAT 15.4 p.9156). A step without it is a user error and
   prints nothing. Data: invented. */
options nocenter;
title;
data estimates;
length Variable $8 _Scale_ $8;
Variable='Trt'; _Scale_='MLE'; _Stage_=1; Estimate=-7; StdErr=4.5;
run;
proc seqtest parms(testvar=Trt)=estimates;
run;
