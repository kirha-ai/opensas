/* PARSE-twolevelset: an undeclared two-level `libref.member` in SET must not
   ParseError — the step parses, then fails at execution like real SAS
   ("File ... does not exist", BUG-setmissingquiet). The positive step runs
   FIRST because the error puts the rest of the program in syntax-check mode
   (BUG-errhalt).
   expect-rc: 1 */
data have; x = 10; output; x = 20; output; run;
data _null_;
  set have;
  put "have x=" x;
run;
data _null_;
  set ghostlib.ghost;
  put "unreachable - the missing SET errors before this";
run;
