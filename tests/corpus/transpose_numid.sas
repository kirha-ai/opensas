data have; input visit v; datalines;
1 100
2 200
;
run;
proc transpose data=have out=want; id visit; var v; run;
proc print data=want noobs; run;
