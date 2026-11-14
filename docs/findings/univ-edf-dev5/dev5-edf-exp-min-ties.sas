options ls=256;ods graphics off;ods exclude all;
data d;do grp=1 to 3;do i=1 to 10;if i<=grp then x=1;else x=i-grp+1;output;end;end;run;
ods output GoodnessOfFit=gof;
proc univariate data=d noprint;by grp;histogram x / noplot exponential(theta=est sigma=4);run;
ods exclude none;
data _null_;set gof;file print;put grp best8. '|' TestLab '|' Stat best32. '|' pValue best32. '|' pSign;run;
