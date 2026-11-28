/* STAT-FASTCLUS-001: PROC FASTCLUS roles and options on invented data:
 * BY groups (two analyses), FREQ (a FREQ=0 observation is left out of the
 * analysis but still assigned in OUT=), NOMISS (all-missing and partially
 * missing rows omitted and counted), ID, OUT= CLUSTER/DISTANCE; the default
 * MAXITER=1 listing (no iteration history); MAXITER= reached without
 * convergence with VARIABLESAREUNCORRELATED on SASHELP.IRIS. Expected
 * listings are SAS 9.4 output of these same steps (NOBYLINE; the OUT= values
 * were read from a SAS PROC PRINT of the same OUT= data set).
 * Blank lines between steps and at the end follow the opensas listing
 * convention (every other line and token is the SAS text).
 */
options nodate nonumber nocenter linesize=160 pagesize=max nobyline;
title; footnote;
data pts;
  input g $ id $ x y f;
  datalines;
A a1 1 1 1
A a2 2 1 2
A a3 1 2 1
A a4 8 8 1
A a5 9 8 1
A a6 8 9 3
A a7 . . 1
A a8 4 . 1
A a9 5 5 0
B b1 0 0 1
B b2 0 1 1
B b3 10 0 1
B b4 10 1 1
B b5 5 9 1
B b6 6 9 2
;
proc fastclus data=pts maxc=2 maxiter=10 nomiss out=o1;
  var x y; freq f; by g; id id;
run;
data _null_;
  set o1;
  file print;
  put id cluster distance 8.5;
run;
proc fastclus data=pts(where=(g='B')) maxc=3;
  var x y;
run;
proc fastclus data=sashelp.iris maxc=4 maxiter=2 variablesareuncorrelated;
  var SepalLength PetalLength;
run;
