data d;input x;do i=1 to 4;w=1e-120;output;end;datalines;
1e+200
;
run;proc univariate data=d noprint;var x;weight w;output out=q n=n mean=m sum=s css=c uss=u std=d;run;data _null_;set q;nm=m/1e200;ns=s/(1e-120)/1e200;mc=missing(c);nmom=nmiss(m,s,c,u,d);file print;put 'EXT ' n 3. ' ' nm best24. ' ' ns best24. ' ' mc 2. ' ' nmom 2.;run;
