data _null_; file print; put 'Case univ_weight_default'; run;
data sample;input x w;datalines;
1 1
2 3
9 0
10 -1
7 .
;
run;

proc univariate data=sample  noprint;var x;weight w;output out=summary n=n mean=m;run;
data _null_;file print;set summary;put 'WEIGHTS ' n 4. m 12.6;run;

data _null_; file print; put 'Case univ_weight_exclnpwgt'; run;
data sample;input x w;datalines;
1 1
2 3
9 0
10 -1
7 .
;
run;

proc univariate data=sample exclnpwgt noprint;var x;weight w;output out=summary n=n mean=m;run;
data _null_;file print;set summary;put 'WEIGHTS ' n 4. m 12.6;run;

data _null_; file print; put 'Case univ_weight_exclnpwgts'; run;
data sample;input x w;datalines;
1 1
2 3
9 0
10 -1
7 .
;
run;

proc univariate data=sample exclnpwgts noprint;var x;weight w;output out=summary n=n mean=m;run;
data _null_;file print;set summary;put 'WEIGHTS ' n 4. m 12.6;run;
