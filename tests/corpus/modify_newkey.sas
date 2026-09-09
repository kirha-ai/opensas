data m;
  input id x;
  datalines;
1 10
2 20
;
run;
data t;
  input id x;
  datalines;
2 22
5 55
;
run;
/* Language Reference: Concepts p.601 revised program: a MODIFY … BY no-match (_IORC_ = _DSENMR =
   1230015 — the literal; %SYSRC is GAP-sysrcmacro) is added by the PROGRAM
   with an explicit OUTPUT, not fabricated by MODIFY. _ERROR_ is cleared so
   no ERROR is raised and the step (and PROC PRINT) runs to completion;
   matched keys take the explicit REPLACE. */
data m;
  modify m t;
  by id;
  if _iorc_ = 1230015 then do;
    output;
    _error_ = 0;
  end;
  else replace;
run;
proc print data=m noobs; run;
