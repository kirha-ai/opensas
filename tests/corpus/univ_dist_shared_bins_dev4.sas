options nodate nonumber;
data d;input c $ x y;datalines;
A 0 100
A 1 101
B 10 200
B 12 202
;
proc univariate data=d noprint;class c / keylevel='B';var x y;
histogram x y / noplot outhistogram=hkey;run;
proc univariate data=d noprint;class c / keylevel='B';var x y;
histogram x y / noplot midpoints=uniform outhistogram=huniform;run;
proc univariate data=d noprint;class c;var x y;
histogram x y / noplot nmidpoints=4 outhistogram=hcount;run;
proc univariate data=d noprint;class c;var x y;
histogram x y / noplot endpoints=0 to 15 by 5 maxnbin=2 outhistogram=hwindow;run;
data flat;do i=1 to 4;x=5;output;end;run;
proc univariate data=flat noprint;
histogram x / noplot normal(mu=5 sigma=1 noprint) outhistogram=ch outkernel=ck;run;
data ks;set ck end=eof;retain first;
if _n_=1 then first=_value_;
if eof then do;last=_value_;n=_n_;output;end;
keep first last n;run;
data _null_;set hkey(in=a) huniform(in=b) hcount(in=counted) hwindow(in=windowed) ch(in=constant) ks(in=kernel);
file print;
if kernel then put 'G ' first 8.5 ' ' last 10.7 ' ' n 4.;
else if constant then do;
 blank=missing(_curve_);absent=missing(_exppct_);
 put 'C ' _midpt_ 6.2 ' ' _count_ 3. ' ' blank 1. ' ' absent 1.;
end;
else if windowed then put 'W ' c $1. ' ' _var_ $1. ' ' _minpt_ 8.2 ' ' _count_ 3.;
else do;
 if a then id='K';else if b then id='U';else id='N';
 put id $1. ' ' c $1. ' ' _var_ $1. ' ' _midpt_ 8.2 ' ' _count_ 3.;
end;run;
