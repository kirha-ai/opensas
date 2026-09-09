/* GAP-putnamedcase + BUG-putallcase (one renderer): pins the Language
   Reference: Concepts p.537 rule that PUT's named form labels with the
   variable's DEFINED case, while FIRST./LAST. prefixes and the automatics
   are uppercase — p.537's log shows `put _n_= … first.<var>=` rendering as
   `_N_=1 FIRST.<Var>=1`; p.539: `first.x=` renders `FIRST.x=1`; `put _all_`
   renders `_ERROR_=0 _N_=1` while user variables keep their defined case. */
data lots; Qty=1; Region="N"; output; Qty=2; Region="S"; output; run;
data _null_; set lots; by Region;
  put _n_= first.region= qty=;
  put _all_;
run;
