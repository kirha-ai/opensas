data d;do i=1 to 40;u=((i-.5)/40)**1.5;
x=sqrt(-2*log1px(-u));gp=((1-u)**(-.3)-1)/.3;output;end;run;
ods exclude all;ods output GoodnessOfFit=g;proc univariate data=d noprint;histogram gp / noplot pareto(sigma=1 edfseed=13579 edfnsamples=5);run;ods exclude none;data _null_;set g;file print;put 'STAT ' TestLab '|' Stat best32.;run;
