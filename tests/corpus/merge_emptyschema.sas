/* BUG-setpdvschema / TRIAGE-gen2values (EG VISITNUM shape): a zero-row
   source's schema is CERTAIN and must correct the compile pass's char guess
   for v (guessed from the v="99" below); the char value then converts to
   numeric the SAS way. Covers BOTH drivers: MERGE (pre-declared since
   a61a220) and plain SET (buildDriver pre-declare, BUG-setpdvschema). */
data empty;
  v = 1; w = 2;
  delete;
run;
data rows;
  k = 1;
run;
data t;
  merge empty rows;
  v = "99";
  vt = vtype(v);
run;
data _null_;
  set t;
  put "MERGE " vt= v= w=;
run;
data s;
  set empty rows;
  v = "99";
  vt = vtype(v);
run;
data _null_;
  set s;
  put "SET " vt= v= w=;
run;
