data d;input x;w=1e-140;datalines;
1e155
-1e155
3
4
;
run;proc univariate data=d noprint;var x;weight w;output out=q mean=m sum=s css=c uss=u std=d;run;data _null_;set q;su=s/1e-140;mn=nmiss(c,u,d);file print;put 'EXT ' m best24. ' ' su best24. ' ' mn 2.;run;
