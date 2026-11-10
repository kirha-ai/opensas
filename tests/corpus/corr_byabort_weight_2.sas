/* BUG-corrbygroupabort: expect-rc: 1.
   SAS 9.4 CORR BY statement, Statistical Procedures p.16: separate analyses.
   Oracle: /tmp/opensas-review-fixes/BUG-corrbygroupabort/weight_2.sas/.log/.txt
   One ERROR for g=2; both valid groups: N=3, r=.96077, p=.1789.
   Golden uses opensas listing layout; failed-group headers are omitted. */
data d; input g x y f; datalines;
1 3 5 1
1 4 8 1
1 5 9 1
2 3 5 0
2 4 8 0
2 5 9 0
3 3 5 1
3 4 8 1
3 5 9 1
;
run;
proc corr data=d; by g; var x y; weight f; run;
