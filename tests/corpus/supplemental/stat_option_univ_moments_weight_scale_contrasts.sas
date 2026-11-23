data _null_; file print; put 'Case univ_moments_weight_scale_501'; run;
data d;input x raw;unit=2**(-501);w=raw*unit;datalines;
1 1
2 2
5 3
9 4
;
run;proc univariate data=d noprint idout vardef=weight;var x;weight w;id unit;output out=t n=n sumwgt=sw sum=sm mean=m css=c var=v;run;data _null_;set t;wn=sw/unit;sn=sm/unit;cn=c/unit;file print;put 'MOMENT ' n best32. ' ' wn best32. ' ' sn best32. ' ' m best32. ' ' cn best32. ' ' v best32.;run;

data _null_; file print; put 'Case univ_moments_weight_scale_502'; run;
data d;input x raw;unit=2**(-502);w=raw*unit;datalines;
1 1
2 2
5 3
9 4
;
run;proc univariate data=d noprint idout vardef=weight;var x;weight w;id unit;output out=t n=n sumwgt=sw sum=sm mean=m css=c var=v;run;data _null_;set t;wn=sw/unit;sn=sm/unit;cn=c/unit;file print;put 'MOMENT ' n best32. ' ' wn best32. ' ' sn best32. ' ' m best32. ' ' cn best32. ' ' v best32.;run;

data _null_; file print; put 'Case univ_moments_weight_scale_503'; run;
data d;input x raw;unit=2**(-503);w=raw*unit;datalines;
1 1
2 2
5 3
9 4
;
run;proc univariate data=d noprint idout vardef=weight;var x;weight w;id unit;output out=t n=n sumwgt=sw sum=sm mean=m css=c var=v;run;data _null_;set t;wn=sw/unit;sn=sm/unit;cn=c/unit;file print;put 'MOMENT ' n best32. ' ' wn best32. ' ' sn best32. ' ' m best32. ' ' cn best32. ' ' v best32.;run;

data _null_; file print; put 'Case univ_moments_weight_scale_504'; run;
data d;input x raw;unit=2**(-504);w=raw*unit;datalines;
1 1
2 2
5 3
9 4
;
run;proc univariate data=d noprint idout vardef=weight;var x;weight w;id unit;output out=t n=n sumwgt=sw sum=sm mean=m css=c var=v;run;data _null_;set t;wn=sw/unit;sn=sm/unit;cn=c/unit;file print;put 'MOMENT ' n best32. ' ' wn best32. ' ' sn best32. ' ' m best32. ' ' cn best32. ' ' v best32.;run;

data _null_; file print; put 'Case univ_moments_weight_scale_505'; run;
data d;input x raw;unit=2**(-505);w=raw*unit;datalines;
1 1
2 2
5 3
9 4
;
run;proc univariate data=d noprint idout vardef=weight;var x;weight w;id unit;output out=t n=n sumwgt=sw sum=sm mean=m css=c var=v;run;data _null_;set t;wn=sw/unit;sn=sm/unit;cn=c/unit;file print;put 'MOMENT ' n best32. ' ' wn best32. ' ' sn best32. ' ' m best32. ' ' cn best32. ' ' v best32.;run;

data _null_; file print; put 'Case univ_moments_weight_scale_600'; run;
data d;input x raw;unit=2**(-600);w=raw*unit;datalines;
1 1
2 2
5 3
9 4
;
run;proc univariate data=d noprint idout vardef=weight;var x;weight w;id unit;output out=t n=n sumwgt=sw sum=sm mean=m css=c var=v;run;data _null_;set t;wn=sw/unit;sn=sm/unit;cn=c/unit;file print;put 'MOMENT ' n best32. ' ' wn best32. ' ' sn best32. ' ' m best32. ' ' cn best32. ' ' v best32.;run;
