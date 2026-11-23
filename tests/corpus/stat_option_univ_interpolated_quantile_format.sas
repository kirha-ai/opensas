data sample; input x; datalines;
1
2
2
4
5
7
8
9
;
run;

ods output Quantiles=quantiles;
proc univariate data=sample;var x;run;
data _null_;file print;ds=open('quantiles');i=varnum(ds,'Estimate');
name=varfmt(ds,i);put 'QFMT ' name;rc=close(ds);run;
