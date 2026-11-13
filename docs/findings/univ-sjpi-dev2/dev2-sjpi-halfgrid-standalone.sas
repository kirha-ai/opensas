ods graphics off;
data d;input x :hex16.;datalines;
C01FF5C28F5C28F6
C01BCCCCCCCCCCCD
C015147AE147AE15
C00CB851EB851EB9
BFEFAE147AE147B1
3FDF5C28F5C28F58
4010AE147AE147AE
4020051EB851EB85
;
proc univariate data=d noprint;var x;output out=s qrange=q std=sd;histogram x / noplot kernel(c=sjpi) outkernel=k;run;
data _null_;set s;file print;put "STATS id=15 " q=best32. sd=best32.;run;
data _null_;set k(obs=1);file print;put "RESULT id=15 " _c_=best32.;run;
data d;input x :hex16.;datalines;
C020000000000000
C01BD70A3D70A3D7
C0151EB851EB851F
C00CCCCCCCCCCCCD
BFF0000000000000
3FDEB851EB851EB8
4010A3D70A3D70A4
4020000000000000
;
proc univariate data=d noprint;var x;output out=s qrange=q std=sd;histogram x / noplot kernel(c=sjpi) outkernel=k;run;
data _null_;set s;file print;put "STATS id=13 " q=best32. sd=best32.;run;
data _null_;set k(obs=1);file print;put "RESULT id=13 " _c_=best32.;run;
data d;input x :hex16.;datalines;
C020000000000000
C01BD70A3D70A3D7
C0151EB851EB851F
C00CCCCCCCCCCCCD
C008000000000001
3FDEB851EB851EB8
4010A3D70A3D70A4
4020000000000000
;
proc univariate data=d noprint;var x;output out=s qrange=q std=sd;histogram x / noplot kernel(c=sjpi) outkernel=k;run;
data _null_;set s;file print;put "STATS id=0 " q=best32. sd=best32.;run;
data _null_;set k(obs=1);file print;put "RESULT id=0 " _c_=best32.;run;
data d;input x :hex16.;datalines;
C01FF5C28F5C28F6
C01BCCCCCCCCCCCD
C015147AE147AE15
C00CB851EB851EB9
BFEFAE147AE147B0
3FDF5C28F5C28F58
4010AE147AE147AE
4020051EB851EB85
;
proc univariate data=d noprint;var x;output out=s qrange=q std=sd;histogram x / noplot kernel(c=sjpi) outkernel=k;run;
data _null_;set s;file print;put "STATS id=16 " q=best32. sd=best32.;run;
data _null_;set k(obs=1);file print;put "RESULT id=16 " _c_=best32.;run;
data d;input x :hex16.;datalines;
C020000000000000
C01BD70A3D70A3D7
C0151EB851EB851F
C00CCCCCCCCCCCCD
BFF0000000000001
3FDEB851EB851EB8
4010A3D70A3D70A4
4020000000000000
;
proc univariate data=d noprint;var x;output out=s qrange=q std=sd;histogram x / noplot kernel(c=sjpi) outkernel=k;run;
data _null_;set s;file print;put "STATS id=12 " q=best32. sd=best32.;run;
data _null_;set k(obs=1);file print;put "RESULT id=12 " _c_=best32.;run;
data d;input x :hex16.;datalines;
C020000000000000
C01BD70A3D70A3D7
C0151EB851EB851F
C00CCCCCCCCCCCCD
C008000000000000
3FDEB851EB851EB8
4010A3D70A3D70A4
4020000000000000
;
proc univariate data=d noprint;var x;output out=s qrange=q std=sd;histogram x / noplot kernel(c=sjpi) outkernel=k;run;
data _null_;set s;file print;put "STATS id=1 " q=best32. sd=best32.;run;
data _null_;set k(obs=1);file print;put "RESULT id=1 " _c_=best32.;run;
data d;input x :hex16.;datalines;
C01FF5C28F5C28F6
C01BCCCCCCCCCCCD
C015147AE147AE15
C00CB851EB851EB9
BFEFAE147AE147AF
3FDF5C28F5C28F58
4010AE147AE147AE
4020051EB851EB85
;
proc univariate data=d noprint;var x;output out=s qrange=q std=sd;histogram x / noplot kernel(c=sjpi) outkernel=k;run;
data _null_;set s;file print;put "STATS id=17 " q=best32. sd=best32.;run;
data _null_;set k(obs=1);file print;put "RESULT id=17 " _c_=best32.;run;
data d;input x :hex16.;datalines;
C020000000000000
C01BD70A3D70A3D7
C0151EB851EB851F
C00CCCCCCCCCCCCD
BFEFFFFFFFFFFFFF
3FDEB851EB851EB8
4010A3D70A3D70A4
4020000000000000
;
proc univariate data=d noprint;var x;output out=s qrange=q std=sd;histogram x / noplot kernel(c=sjpi) outkernel=k;run;
data _null_;set s;file print;put "STATS id=14 " q=best32. sd=best32.;run;
data _null_;set k(obs=1);file print;put "RESULT id=14 " _c_=best32.;run;
data d;input x :hex16.;datalines;
C020000000000000
C01BD70A3D70A3D7
C0151EB851EB851F
C00CCCCCCCCCCCCD
C007FFFFFFFFFFFF
3FDEB851EB851EB8
4010A3D70A3D70A4
4020000000000000
;
proc univariate data=d noprint;var x;output out=s qrange=q std=sd;histogram x / noplot kernel(c=sjpi) outkernel=k;run;
data _null_;set s;file print;put "STATS id=2 " q=best32. sd=best32.;run;
data _null_;set k(obs=1);file print;put "RESULT id=2 " _c_=best32.;run;
