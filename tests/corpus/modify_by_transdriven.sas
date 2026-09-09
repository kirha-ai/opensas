/* BUG-modifybymasterdriven: `MODIFY master trans; BY k;` is TRANSACTION-driven —
   one DATA-step iteration per TRANSACTION observation, never one per master row.
   Language Reference: Concepts p.596 counts exactly 3 REPLACEs + 3 OUTPUTs = the 6 transaction rows of
   the p.595 program, and p.599 Table 23.4 has NO _IORC_ code for "a master row
   with no transaction" because that iteration does not exist.  (UPDATE's
   master-driven, group-collapsing driver — correct for UPDATE, p.586 Step 2 —
   used to run MODIFY too, giving every master row a _SOK iteration.) */

data m; input k stock; datalines;
1 100
2 200
3 300
;
run;
data t; input k stock; datalines;
2 999
;
run;

/* 3 master rows, 1 transaction -> exactly ONE iteration (k=2, _IORC_=_SOK);
   k=1 and k=3 are never read into the PDV.  The implicit REPLACE applies the
   transaction overlay to the matched obs; the untouched master rows are
   re-emitted byte-identical (in-place guarantee). */
title 'one iteration per transaction row; unmatched master rows never visited';
data m; modify m t; by k; put 'ITER k=' k ' iorc=' _iorc_; run;
proc print data=m noobs; run;

/* p.599 Table 23.4: consecutive transaction obs with the same unmatched BY
   value EACH get an iteration — the first returns _DSENMR (1230015), the
   subsequent ones _DSEMTR.  _DSEMTR's numeric value is oracle-blocked
   (NOTE-modifydsemtr; %sysrc(_dsemtr) fails loud by design), so opensas
   stamps a DISTINCT non-SAS sentinel (-1230015) rather than guessing a number
   a %SYSRC comparison could silently match.  The master row (k=1) is never
   visited and survives the step intact. */
title 'consecutive unmatched transactions: _DSENMR then _DSEMTR, two iterations';
data m2; input k x; datalines;
1 10
;
run;
data t2; input k a; datalines;
9 90
9 91
;
run;
data m2; modify m2 t2; by k; put 'k=' k ' _iorc_=' _iorc_; _error_=0; run;
proc print data=m2 noobs; run;

/* p.588 Table 23.3 "Duplicate BY-values": MODIFY with BY allows duplicates in
   BOTH data sets — each transaction matches the NEXT master obs with that key:
   x=10+100=110, then x=11+200=211; the k=2 master obs is never visited. */
title 'duplicate BY values in master and transaction match in order';
data m3; input k x; datalines;
1 10
1 11
2 20
;
run;
data t3; input k a; datalines;
1 100
1 200
;
run;
data m3; modify m3 t3; by k; x=x+a; run;
proc print data=m3 noobs; run;
