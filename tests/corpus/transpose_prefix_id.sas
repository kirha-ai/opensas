/* PREFIX= with ID: the prefix is ATTACHED to the ID value (dt_1), it is NOT
   ignored — a real EPOCH macro's six transposes (prefix=dt_/dt2_/dtm_/...)
   are distinguished only by it, and identical _1.._N names silently collide
   in the downstream MERGE (QA-transprefixid). Numeric-ID-without-prefix (_1)
   stays covered by transpose_numid. */
data t2;
  input STUDYID $ USUBJID $ OBSID EV_DT;
  datalines;
S1 P1 1 100
S1 P1 2 200
S1 P1 3 300
S1 P2 1 150
S1 P2 2 250
;
run;
proc transpose data=t2 out=tp prefix=dt_;
  by STUDYID USUBJID;
  var EV_DT;
  id OBSID;
run;
proc print data=tp noobs; run;
