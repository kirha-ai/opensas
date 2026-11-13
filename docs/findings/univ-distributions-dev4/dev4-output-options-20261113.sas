/* Output WHERE uses the renamed descriptor; each output owns its options. */
options nodate nonumber;
proc format;value groupfmt 1,2='A' 3,4='B';run;
data d;input b c x f;format c groupfmt.;label c='Synthetic group';datalines;
1 2 1 0
1 1 2 1
1 2 4 1
1 4 6 1
1 3 8 1
2 2 1 1
2 1 3 1
2 3 5 1
2 4 7 1
;
proc univariate data=d noprint;by b;class c;freq f;var x;
histogram x / noplot endpoints=0 to 10 by 2 kernel(c=.5)
 outhist=work.h(where=(n>0) keep=b c _minpt_ _count_ rename=(_count_=n))
 outkernel=work.k(keep=b c _value_ _density_ rename=(_value_=v _density_=density) where=(v=2));
run;
data _null_;set h(in=histogram) k;file print;
if histogram then put 'H ' b 1. ' ' c 1. ' ' _minpt_ 2. ' ' n 1.;
else put 'K ' b 1. ' ' c 1. ' ' v 2. ' ' density 12.8;
run;
proc contents data=h out=hm noprint;run;
proc sort data=hm;by varnum;run;
data _null_;set hm;file print;put name= type= length= label= format=;run;
