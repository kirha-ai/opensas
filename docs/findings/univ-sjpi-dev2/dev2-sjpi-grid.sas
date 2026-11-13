ods graphics off;
data d; input x @@; datalines;
-8 -3 -2 -1 0 1 2 3 8
;
%macro p(id,opts);
proc univariate data=d noprint;histogram x / noplot kernel(c=sjpi) outkernel=k &opts;run;
data _null_;set k(obs=1);file print;put "&id " _c_=best32.;run;
%mend;
%p(default,);
%p(wide,%str(endpoints=-100 to 100 by 10));
%p(narrow,%str(endpoints=-8 to 8 by 1));
%p(mid,%str(midpoints=-8 to 8 by 2));
data d;set d;x=x+100;run;
%p(shift,);
data d;set d;x=(x-100)*1000;run;
%p(scale,);
