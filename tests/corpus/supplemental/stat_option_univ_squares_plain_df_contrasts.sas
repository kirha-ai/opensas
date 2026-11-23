data _null_; file print; put 'Case univ_squares_plain_df_0p25'; run;
data d;input z w f;u=2**(-511);x=z*0.25*u;datalines;
-1 1 1
-1 1 1
0 1 1
1 1 1
1 1 1
;
run;proc univariate data=d noprint idout vardef=df;var x;id u;output out=q std=d uss=us css=cs;run;data _null_;set q;nd=d/u;nu=us/u/u;nc=cs/u/u;file print;put 'SQUARE ' nd best32. ' ' nu best32. ' ' nc best32.;run;

data _null_; file print; put 'Case univ_squares_plain_df_0p5'; run;
data d;input z w f;u=2**(-511);x=z*0.5*u;datalines;
-2 .5 1
-.5 1 2
0 1 1
1 2 1
1 4 2
;
run;proc univariate data=d noprint idout vardef=df;var x;id u;output out=q std=d uss=us css=cs;run;data _null_;set q;nd=d/u;nu=us/u/u;nc=cs/u/u;file print;put 'SQUARE ' nd best32. ' ' nu best32. ' ' nc best32.;run;

data _null_; file print; put 'Case univ_squares_plain_df_0p71'; run;
data d;input z w f;u=2**(-511);x=z*0.71*u;datalines;
-2 .5 1
-.5 1 2
0 1 1
1 2 1
1 4 2
;
run;proc univariate data=d noprint idout vardef=df;var x;id u;output out=q std=d uss=us css=cs;run;data _null_;set q;nd=d/u;nu=us/u/u;nc=cs/u/u;file print;put 'SQUARE ' nd best32. ' ' nu best32. ' ' nc best32.;run;

data _null_; file print; put 'Case univ_squares_plain_df_0p99'; run;
data d;input z w f;u=2**(-511);x=z*0.99*u;datalines;
-1 1 1
-1 1 1
0 1 1
1 1 1
1 1 1
;
run;proc univariate data=d noprint idout vardef=df;var x;id u;output out=q std=d uss=us css=cs;run;data _null_;set q;nd=d/u;nu=us/u/u;nc=cs/u/u;file print;put 'SQUARE ' nd best32. ' ' nu best32. ' ' nc best32.;run;

data _null_; file print; put 'Case univ_squares_plain_df_1'; run;
data d;input z w f;u=2**(-511);x=z*1*u;datalines;
-1 1 1
-1 1 1
0 1 1
1 1 1
1 1 1
;
run;proc univariate data=d noprint idout vardef=df;var x;id u;output out=q std=d uss=us css=cs;run;data _null_;set q;nd=d/u;nu=us/u/u;nc=cs/u/u;file print;put 'SQUARE ' nd best32. ' ' nu best32. ' ' nc best32.;run;

data _null_; file print; put 'Case univ_squares_plain_df_1p25'; run;
data d;input z w f;u=2**(-511);x=z*1.25*u;datalines;
-1 1 1
-1 1 1
0 1 1
1 1 1
1 1 1
;
run;proc univariate data=d noprint idout vardef=df;var x;id u;output out=q std=d uss=us css=cs;run;data _null_;set q;nd=d/u;nu=us/u/u;nc=cs/u/u;file print;put 'SQUARE ' nd best32. ' ' nu best32. ' ' nc best32.;run;
