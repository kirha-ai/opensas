/* FEAT-univ-inference. SAS Statistical Procedures pp.414-421,444-447.
   Oracle: sasrun /abs/tests/corpus/univ_inference_output.sas -f text
   Core SW=.97485827830837 p=.93316533637933; n21 signed-rank p=9.1830084743323E-8. */
options nodate nonumber;
data d;
do b=1 to 2; do c=1 to 2; do i=1 to 8;
x=i+b-1;y=2*x;f=1;w=1;output;
end;end;end;
run;
proc univariate data=d noprint normaltest forceqn forcesn location=4.5 9;
by b;class c;freq f;var x y;
output out=o normaltest=sw probn=pn t=t ty probt=pt pty msign=m probm=pm signrank=s probs=ps gini=g mad=mad sn=sn qn=qn std_gini=sg std_mad=sm std_sn=ss std_qn=sq std_qrange=si;
output out=q pctlpts=10 50 90 pctlpre=p ciquantdf=(type=asymmetric lowerpre=l upperpre=u) ciquantnormal=(alpha=.1 lowerpre=nl upperpre=nu);
run;
data _null_;set o;file print;
put 'NORMAL ' b= c= sw 12.8 pn 12.8;
put 'LOCATION ' t 12.6 ty 12.6 pt 12.6 pty 12.6 m 8.3 pm 12.6 s 8.3 ps 12.6;
put 'ROBUST ' g 12.6 mad 12.6 sn 12.6 qn 12.6 sg 12.6 sm 12.6 ss 12.6 sq 12.6 si 12.6;
run;
data _null_;set q;file print;
put 'CI ' b= c= l10= u10= l50= u50= l90= u90=;
put 'NORMALCI ' nl10 12.6 nu10 12.6 nl50 12.6 nu50 12.6 nl90 12.6 nu90 12.6;
run;
proc univariate data=d noprint alpha=.1;
by b;class c;var x;
output out=l pctlpts=25 50 pctlpre=p cipctldf=(type=lower lowerpre=l upperpre=u) cipctlnormal=(type=upper lowerpre=nl upperpre=nu);
run;
data _null_;set l;file print;put 'ONESIDED ' b= c= l25= u25= l50= u50= nl25= nu25 12.6 ' ' nl50= nu50 12.6;run;
data ranks;do n=20,21,30;do i=1 to n;x=mod(i,7)-2.5;output;end;end;run;
proc univariate data=ranks noprint;by n;var x;output out=r signrank=s probs=p;run;
data _null_;set r;file print;put 'RANK ' n= s 8.3 p 12.8;run;
