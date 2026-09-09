/* doc-finder tick172: PROC RANK TIES=LOW/HIGH/DENSE + missing exclusion —
   previously only TIES=MEAN was pinned. Verified vs SAS 9.4 Procedures Guide:
   values 10,20,20,30 -> LOW 1,2,2,4 ; HIGH 1,3,3,4 ; DENSE 1,2,2,3.
   A missing value is excluded from ranking and stays missing. */
data d; input id v; datalines;
1 10
2 20
3 20
4 30
;
run;
proc rank data=d out=lo ties=low;  var v; ranks r; run;
proc print data=lo noobs; run;
proc rank data=d out=hi ties=high; var v; ranks r; run;
proc print data=hi noobs; run;
proc rank data=d out=de ties=dense; var v; ranks r; run;
proc print data=de noobs; run;
data m; input id v; datalines;
1 5
2 .
3 15
4 25
;
run;
proc rank data=m out=mr; var v; ranks r; run;
proc print data=mr noobs; run;
