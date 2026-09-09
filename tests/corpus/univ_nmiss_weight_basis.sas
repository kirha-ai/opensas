/* BUG-univnmissweightbasis: the missing count's EXCLUSION BASIS with a WEIGHT
   variable. Base SAS 9.4 Procedures Guide: Statistical Procedures, printed
   p.408 (`=== pdf 411 ===`, offset +3, running header FOLLOWS the marker —
   D-020) carries TWO DIFFERENT exclusion lists:

     list 1 (the ANALYSIS):  FREQ missing-or-nonpositive and WEIGHT missing
                             exclude the observation;
     list 2 (the NMISS basis): pre-excludes only nonpositive FREQ, and
                             missing-or-nonpositive WEIGHT **only under
                             EXCLNPWGT**.

   So without EXCLNPWGT an obs with a missing WEIGHT leaves the analysis (N)
   but stays in the count basis — and a PRESENT value there is not missing.
   `nmiss = total - N` is correct in every other case and wrong exactly here:
   it counts row 7 below (x=7 present, wt missing) as missing → 5, not 4.
   The fix counts missing analysis cells directly; the basis's own
   pre-exclusions were already gone from the row set (expandFreq /
   dropNonpositiveWeight).

   Probe (8 obs): x=1 . 3 . 5 . 7 . / wt=1 1 0 0 1 1 . . / f=1 1 1 1 0 0 1 1
   pins every combination that distinguishes the two lists:

     * control, no WEIGHT/FREQ          -> n=4 nmiss=4   (unchanged)
     * WEIGHT, no EXCLNPWGT  (THE BUG)  -> n=3 nmiss=4   (was nmiss=5: row 7's
        x=7 is present; N drops it, the basis does not; 3+4=7 != 8 is the
        doc's own asymmetry, not an arithmetic slip)
     * WEIGHT + EXCLNPWGT (via MEANS — UNIVARIATE rejects the option loud,
       a separate gap)                -> n=2 nmiss=2, _FREQ_=4 (rows leave
        the denominator entirely; unchanged by the fix)
     * nonpositive WEIGHT both ways    -> in the same columns: x=3/wt=0 stays
        in N without EXCLNPWGT (3), leaves under EXCLNPWGT (2)
     * nonpositive FREQ                 -> n=3 nmiss=3   (already matched
        list 2; pinned so the fix cannot move it: 3+3=6=8-2)
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

title "THE BUG: weight wt, no EXCLNPWGT -> n=3 nmiss=4 (row 7: x=7 PRESENT, only wt missing)";
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
