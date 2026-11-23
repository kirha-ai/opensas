data _null_; file print; put 'Case univ_class_nested_freq_data'; run;
proc format;value k 1,3='X' 2,4='Y';run;
data d;input g a b y w f;datalines;
1 2 12 1 . 1
1 3 2 2 1 1
1 1 12 4 1 2
1 2 10 8 1 3
1 4 12 16 1 1
1 2 2 32 1 1
1 3 10 64 1 1
2 1 10 128 1 1
2 4 12 256 1 2
2 3 2 512 1 3
2 2 10 1024 1 1
;
run;
proc univariate data=d noprint;by g;class a(order=freq) b(order=data);format a k.;var y;weight w;freq f;output out=o n=n sum=s;run;data _null_;set o;file print;put 'GROUP ' g 1. a 2. b 3. n 3. s 6.;run;

data _null_; file print; put 'Case univ_class_nested_freq_formatted'; run;
proc format;value k 1,3='X' 2,4='Y';run;
data d;input g a b y w f;datalines;
1 2 12 1 . 1
1 3 2 2 1 1
1 1 12 4 1 2
1 2 10 8 1 3
1 4 12 16 1 1
1 2 2 32 1 1
1 3 10 64 1 1
2 1 10 128 1 1
2 4 12 256 1 2
2 3 2 512 1 3
2 2 10 1024 1 1
;
run;
proc univariate data=d noprint;by g;class a(order=freq) b(order=formatted);format a k.;var y;weight w;freq f;output out=o n=n sum=s;run;data _null_;set o;file print;put 'GROUP ' g 1. a 2. b 3. n 3. s 6.;run;

data _null_; file print; put 'Case univ_class_nested_freq_freq'; run;
proc format;value k 1,3='X' 2,4='Y';run;
data d;input g a b y w f;datalines;
1 2 12 1 . 1
1 3 2 2 1 1
1 1 12 4 1 2
1 2 10 8 1 3
1 4 12 16 1 1
1 2 2 32 1 1
1 3 10 64 1 1
2 1 10 128 1 1
2 4 12 256 1 2
2 3 2 512 1 3
2 2 10 1024 1 1
;
run;
proc univariate data=d noprint;by g;class a(order=freq) b(order=freq);format a k.;var y;weight w;freq f;output out=o n=n sum=s;run;data _null_;set o;file print;put 'GROUP ' g 1. a 2. b 3. n 3. s 6.;run;

data _null_; file print; put 'Case univ_class_nested_freq_internal'; run;
proc format;value k 1,3='X' 2,4='Y';run;
data d;input g a b y w f;datalines;
1 2 12 1 . 1
1 3 2 2 1 1
1 1 12 4 1 2
1 2 10 8 1 3
1 4 12 16 1 1
1 2 2 32 1 1
1 3 10 64 1 1
2 1 10 128 1 1
2 4 12 256 1 2
2 3 2 512 1 3
2 2 10 1024 1 1
;
run;
proc univariate data=d noprint;by g;class a(order=freq) b(order=internal);format a k.;var y;weight w;freq f;output out=o n=n sum=s;run;data _null_;set o;file print;put 'GROUP ' g 1. a 2. b 3. n 3. s 6.;run;
