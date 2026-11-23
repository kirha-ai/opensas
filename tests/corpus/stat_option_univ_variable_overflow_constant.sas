data d;input x;do i=1 to 4;w=1;output;end;datalines;
1e+155
;
run;proc univariate data=d noprint;var x;weight w;output out=q n=n mean=m sum=s css=c uss=u std=d;run;data _null_;set q;nm=m/1e155;ns=s/(1)/1e155;mc=missing(c);nmom=nmiss(m,s,c,u,d);file print;put 'EXT ' n 3. ' ' nm best24. ' ' ns best24. ' ' mc 2. ' ' nmom 2.;run;
