ods graphics off;
data all; do id=0 to 100; do v=0 to 3; x=v+id*.001; output; end; end;run;
proc univariate data=all noprint;by id;var x;histogram x / noplot kernel(c=sjpi) outkernel=k;run;
data _null_;set k;by id;file print;if first.id then put id= _c_=best32.;run;
