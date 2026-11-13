ods graphics off;
data j;do i=1 to 101;z=quantile('normal',(i-.375)/(101+.25));u=3+2*sinh((z-.4)/1.2);b=1/(1+exp((.4-z)/1.2));output;end;run;
proc univariate data=j noprint;histogram u / noplot su;histogram b / noplot sb;histogram b / noplot sb(theta=est sigma=est);run;
