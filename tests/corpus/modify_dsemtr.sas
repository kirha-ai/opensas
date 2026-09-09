/* NOTE-modifydsemtr (F8): "p.599 `_DSEMTR`; the behavioural half rides with
   BUG-modifybymasterdriven, only the numeric constant is oracle-blocked."
   VERDICT: VACUOUS today — no live defect. The behavioural half LANDED with
   BUG-modifybymasterdriven (QA sweep tick395 verified it clean end-to-end)
   and is re-probed below: the first unmatched transaction key gets _DSENMR
   (1230015, doc-sourced), a CONSECUTIVE repeat of the same key gets the
   distinct _DSEMTR arm (Statements Ref p.247: "the first observation returns
   _DSENMR and the subsequent observations return _DSEMTR"), a match gets
   _SOK (0) with the whole-obs overlay, and the unmatched key is NOT
   fabricated into the rebuilt master. The numeric _DSEMTR constant is
   oracle-blocked BY DESIGN: no shipped volume assigns it a value (the docs
   give mnemonics only — "The best way to test for values of _IORC_ is with
   the mnemonic codes"), so exec.zig uses a negative stand-in (-1230015) that
   no %SYSRC comparison can silently match, and %sysrc(_dsemtr) FAILS LOUD
   rather than guess (GAP-sysrcmacro, macro.zig:1898 — deliberate). A wrong
   branch can therefore never be taken silently. BECOMES LIVE only when a
   live-SAS oracle (or the SAS autocall source) supplies the real value; then
   it is ~2 lines: exec.zig:982's sentinel plus macro.zig's handleSysrc.
   This fixture pins the behavioural matrix so that landing can only move
   the pinned sentinel line below. */
data master; input k v; datalines;
1 10
2 20
;
run;
data trans; input k v; datalines;
9 99
9 98
1 11
;
run;
data master;
  modify master trans;
  by k;
  if _iorc_ = 1230015 then put 'FIRST-NOMATCH ' k=;
  else if _iorc_ = -1230015 then put 'REPEAT-NOMATCH ' k=;
  else if _iorc_ = 0 then put 'MATCH ' k= v=;
  _error_ = 0;
run;
proc print data=master; run;
