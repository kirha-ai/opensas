/* SE-shaped multi-key sort: PROC SORT BY USUBJID SESTDTC ETCD over a CHARACTER
   ISO date. SESTDTC leads the key, so an earlier date sorts first: SCRN
   (2018-09-13) BEFORE FULT (2019-03-28) for a subject — even though ETCD "FULT"
   < "SCRN" alphabetically. Verifies our sort follows the real SE program's key
   (GAP-sedm-next: the golden was built by an older SE program that ordered
   FULT-first, a program-version skew, not an interpreter diff — ours is correct). */
data se;
  input usubjid $ etcd $ sestdtc : $10.;
  datalines;
S02 FULT 2019-03-28
S02 SCRN 2018-09-13
S01 SCRN 2018-09-13
S01 FULT 2019-04-11
;
run;
proc sort data=se; by usubjid sestdtc etcd; run;
proc print data=se noobs; run;
