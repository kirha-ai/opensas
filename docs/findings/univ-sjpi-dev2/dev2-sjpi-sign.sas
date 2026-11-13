ods graphics off;
data base;input v @@;datalines;
-8 -3 -2 -1 0 1 2 3 8
;
data all;do id=0 to 20;do k=1 to 9;set base point=k;x=v+(id-10)*.01;output;end;end;stop;run;
proc univariate data=all noprint;by id;histogram x / noplot kernel(c=sjpi) outkernel=k;run;
data _null_;set k;by id;file print;if first.id then put id= _c_=best32.;run;
data all;do id=0 to 20;do v=0 to 3;x=v+id-10;output;end;end;run;
proc univariate data=all noprint;by id;histogram x / noplot kernel(c=sjpi) outkernel=k;run;
data _null_;set k;by id;file print;if first.id then put 'n4 ' id= _c_=best32.;run;
