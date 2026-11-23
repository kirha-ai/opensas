/* expect-rc: 1 */
proc format;value gr 1='A' 2='B';run;data d;do g=1,2;do x=1,2;y=x;n=x+g;output;end;end;format g gr.;run;proc freq data=d;by g;weight n;tables x y/binomial(equiv p=.2 margin=.2);run;
