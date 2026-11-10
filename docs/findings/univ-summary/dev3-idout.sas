data d;input g c x f id $;datalines;
1 2 1 0 A
1 1 2 1 B
1 2 3 1 C
;
proc univariate data=d noprint idout;by g;class c;freq f;id id;var x;output out=o mean=m;run;proc print data=o;run;
