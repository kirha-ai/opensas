data _null_; file print; put 'Case univ_class_spaces_c_missing_formatted'; run;
proc format;value spaces 1=' Z' 2='Z' 3=' A' 4='A' 5='  ';
value $csp 'a'=' Z' 'b'='Z' 'c'=' A' 'd'='A' 'e'='  ';run;
data d;input x c $ y;datalines;
1 a 1
2 b 2
3 c 4
4 d 8
5 e 16
;
run;
proc univariate data=d noprint;class c(order=formatted missing);format c $csp.;var y;output out=o n=n sum=s;run;data _null_;set o;file print;put 'GROUP ' n 3. s 6.;run;

data _null_; file print; put 'Case univ_class_spaces_c_missing_freq'; run;
proc format;value spaces 1=' Z' 2='Z' 3=' A' 4='A' 5='  ';
value $csp 'a'=' Z' 'b'='Z' 'c'=' A' 'd'='A' 'e'='  ';run;
data d;input x c $ y;datalines;
1 a 1
2 b 2
3 c 4
4 d 8
5 e 16
;
run;
proc univariate data=d noprint;class c(order=freq missing);format c $csp.;var y;output out=o n=n sum=s;run;data _null_;set o;file print;put 'GROUP ' n 3. s 6.;run;

data _null_; file print; put 'Case univ_class_spaces_c_missing_internal'; run;
proc format;value spaces 1=' Z' 2='Z' 3=' A' 4='A' 5='  ';
value $csp 'a'=' Z' 'b'='Z' 'c'=' A' 'd'='A' 'e'='  ';run;
data d;input x c $ y;datalines;
1 a 1
2 b 2
3 c 4
4 d 8
5 e 16
;
run;
proc univariate data=d noprint;class c(order=internal missing);format c $csp.;var y;output out=o n=n sum=s;run;data _null_;set o;file print;put 'GROUP ' n 3. s 6.;run;
