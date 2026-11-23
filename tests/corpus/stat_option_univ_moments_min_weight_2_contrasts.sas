data _null_; file print; put 'Case univ_moments_min_weight_2_1000'; run;
data d;do x=1 to 2;w=1000*2**(-511);output;end;run;proc univariate data=d noprint vardef=weight idout;var x;weight w;id w;output out=t mean=m css=c var=v;run;data _null_;set t;cn=c/w;file print;put 'LOW ' m best32. ' ' cn best32. ' ' v best32.;run;

data _null_; file print; put 'Case univ_moments_min_weight_2_1001'; run;
data d;do x=1 to 2;w=1001*2**(-511);output;end;run;proc univariate data=d noprint vardef=weight idout;var x;weight w;id w;output out=t mean=m css=c var=v;run;data _null_;set t;cn=c/w;file print;put 'LOW ' m best32. ' ' cn best32. ' ' v best32.;run;

data _null_; file print; put 'Case univ_moments_min_weight_2_500'; run;
data d;do x=1 to 2;w=500*2**(-511);output;end;run;proc univariate data=d noprint vardef=weight idout;var x;weight w;id w;output out=t mean=m css=c var=v;run;data _null_;set t;cn=c/w;file print;put 'LOW ' m best32. ' ' cn best32. ' ' v best32.;run;

data _null_; file print; put 'Case univ_moments_min_weight_2_501'; run;
data d;do x=1 to 2;w=501*2**(-511);output;end;run;proc univariate data=d noprint vardef=weight idout;var x;weight w;id w;output out=t mean=m css=c var=v;run;data _null_;set t;cn=c/w;file print;put 'LOW ' m best32. ' ' cn best32. ' ' v best32.;run;
