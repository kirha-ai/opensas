/* GAP-dropcolon: `drop pfx: ;` / `keep pfx: ;` name-prefix wildcards in the
   DROP/KEEP statements (a real EPOCH macro drops six dtm_/dt_ prefix families this way).
   Previously a loud parse error: "expected ';' after drop". */
data d;
  dtm_a = 1; dtm_b = 2; dt_x = 3; keepme = 4;
  drop dtm_: dt_:;
run;

data _null_;
  set d;
  put keepme=;
run;

data k;
  dtm_a = 1; dtm_b = 2; other = 9;
  keep dtm_:;
run;

data _null_;
  set k;
  put dtm_a= dtm_b=;
run;
