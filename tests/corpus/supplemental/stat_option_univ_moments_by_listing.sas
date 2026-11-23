data d;input g e z;x=2**e+z;datalines;
1 40 0
1 40 1
1 40 2
1 40 4
1 40 5
1 40 7
1 40 11
1 40 11
1 40 20
2 46 0
2 46 1
2 46 2
2 46 4
2 46 5
2 46 7
2 46 11
2 46 11
2 46 20
3 46 20
3 46 11
3 46 11
3 46 7
3 46 5
3 46 4
3 46 2
3 46 1
3 46 0
;
run;ods select Moments;ods output Moments=m;proc univariate data=d;by g;var x;output out=sum1 css=c;output out=sum2 mean=m;run;ods output close;data _null_;set m;if label2='Corrected SS' or label2='Variance' then do;file print;put 'ODS ' g 2. nValue2 best32.;end;run;
