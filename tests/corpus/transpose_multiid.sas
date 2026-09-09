data have; input grp r c y; datalines;
1 1 1 10
1 1 2 20
1 2 1 30
1 2 2 40
;
run;
proc transpose data=have out=want delimiter=X; by grp; id r c; var y; run;
proc print data=want noobs; run;
