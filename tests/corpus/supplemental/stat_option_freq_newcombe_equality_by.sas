data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
data grouped;set sample;do g=1 to 2;output;end;run;proc sort data=grouped;by g;run;proc freq data=grouped;by g;weight w;tables r*c c*r / riskdiff(equal method=newcombe);run;
