data _null_; file print; put 'Case univ_wdf_divisor_high'; run;
data d;u=1e148;w=.5+6000*2**(-53);do z=-1,1;x=z*u;output;end;run;proc univariate data=d noprint vardef=wdf;weight w;var x;output out=q sumwgt=s css=c std=d var=v;run;data _null_;set q;u=1e148;dc=c/u/u;nd=d*sqrt(s-1)/u;nv=v*(s-1)/u/u;nm=nmiss(d,v);file print;put 'WDF ' dc best24. ' ' nd best24. ' ' nv best24. ' ' nm 1.;run;

data _null_; file print; put 'Case univ_wdf_divisor_small'; run;
data d;u=1e145;w=.5+4*2**(-53);do z=-1,1;x=z*u;output;end;run;proc univariate data=d noprint vardef=wdf;weight w;var x;output out=q sumwgt=s css=c std=d var=v;run;data _null_;set q;u=1e145;dc=c/u/u;nd=d*sqrt(s-1)/u;nv=v*(s-1)/u/u;nm=nmiss(d,v);file print;put 'WDF ' dc best24. ' ' nd best24. ' ' nv best24. ' ' nm 1.;run;

data _null_; file print; put 'Case univ_wdf_divisor_zero'; run;
data d;u=1;w=.5+0*2**(-53);do z=-1,1;x=z*u;output;end;run;proc univariate data=d noprint vardef=wdf;weight w;var x;output out=q sumwgt=s css=c std=d var=v;run;data _null_;set q;u=1;dc=c/u/u;nd=d*sqrt(s-1)/u;nv=v*(s-1)/u/u;nm=nmiss(d,v);file print;put 'WDF ' dc best24. ' ' nd best24. ' ' nv best24. ' ' nm 1.;run;
