ods graphics off;
data base;input v @@;datalines;
-8 -3 -2 -1 0 1 2 3 8
;
data all;do id=0 to 20;do k=1 to 9;set base point=k;x=v+(id-10)*.01;output;end;end;stop;run;
data _null_;set all;file print;put id= x=hex16.;run;
