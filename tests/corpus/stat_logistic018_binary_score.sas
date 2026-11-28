/* STAT-LOGISTIC-018: saturated binomial MLE p=r/100; delta SE sqrt(p(1-p)/100).
   S154 physical pp.5855,5898-5900,5943,5956. Independent expected values use
   z(.975)=1.959963984540054. CODE is executed by a new DATA step using TEMP
   and a bare fileref; SCORE retains all six input identifiers and missing rows. */
filename lcode temp;
data train;
input g $ y f;
datalines;
A 1 20
A 0 80
B 1 50
B 0 50
C 1 80
C 0 20
;
data incoming;
length g $8;
id=1; g='C'; output;
id=2; g='A'; output;
id=3; g='B'; output;
id=4; g='unseen'; output;
id=5; g=''; output;
id=6; g='A'; output;
run;
proc logistic data=train noprint;
class g(ref='B') / param=effect;
model y(event='1')=g / gconv=1e-14;
freq f;
code file=lcode lookup=select;
score data=incoming out=scored clm;
run;
data coded;
set incoming;
%include lcode;
run;
filename lcode clear;
data _null_;
set coded;
put id g P_1 8.5 P_0 8.5;
run;
data _null_;
set scored;
put id g P_1 8.5 P_0 8.5 LCL_1 8.5 UCL_1 8.5;
run;
