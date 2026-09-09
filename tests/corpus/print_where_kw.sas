data a; input id v sum by; datalines;
1 10 100 1
2 20 200 2
3 40 300 1
;
run;
proc print data=a noobs; where id>1 and v<30; run;
proc print data=a noobs; where sum=200 and by=2; run;
