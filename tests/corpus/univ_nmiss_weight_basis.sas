/* BUG-univnmissweight: SAS 9.4 Statistical Procedures pp.398,408 excludes
   missing WEIGHT observations from UNIVARIATE NMISS, with or without
   EXCLNPWGT. Count missing analysis cells among eligible rows, not total-N:
   row 7 has present x and missing wt; row 8 has both missing.

   Real SAS evidence: /tmp/opensas-review-fixes/BUG-univnmissweight/
   old_basis.sas/.txt/.log (the original fixture), matrix.sas/.txt/.log.
   The old expected NMISS=4 was a mistaken reading of the manual's lists.
   SAS gives UNIVARIATE N=3 NMISS=3; unweighted control remains 4,4,
   FREQ-only control 3,3. Zero weights remain eligible without EXCLNPWGT.
   Existing MEANS checks below are outside this ticket and remain unchanged.
   expect-rc: 0 */
data d;
  input x wt f;
  datalines;
1 1 1
. 1 1
3 0 1
. 0 1
5 1 0
. 1 0
7 . 1
. . 1
;
run;

title "control: no WEIGHT/FREQ -> n=4 nmiss=4";
proc univariate data=d noprint;
  var x;
  output out=u0 n=n nmiss=nmiss;
run;
proc print data=u0 noobs;
run;

title "weight wt, no EXCLNPWGT -> n=3 nmiss=3 (missing weights excluded)";
proc univariate data=d noprint;
  var x;
  weight wt;
  output out=u1 n=n nmiss=nmiss;
run;
proc print data=u1 noobs;
run;

title "nonpositive FREQ already matched list 2 -> n=3 nmiss=3, must not move";
proc univariate data=d noprint;
  var x;
  freq f;
  output out=u2 n=n nmiss=nmiss;
run;
proc print data=u2 noobs;
run;

title "MEANS mirror, weight wt, no EXCLNPWGT -> N 3, N Miss 4";
proc means data=d n nmiss;
  weight wt;
  var x;
run;

title "MEANS, weight wt + EXCLNPWGT -> N 2, N Miss 2 (basis pre-excludes)";
proc means data=d exclnpwgt n nmiss;
  weight wt;
  var x;
run;

title "MEANS OUT= + EXCLNPWGT -> n=2 nmiss=2, _FREQ_=4";
proc means data=d exclnpwgt noprint;
  weight wt;
  var x;
  output out=m1 n=n nmiss=nmiss;
run;
proc print data=m1 noobs;
run;
