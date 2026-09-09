/* BUG-inputqq: the ?/?? error-suppression modifier in input(str, ?? informat.) —
   the canonical SDTM --ORRES→--STRESN char→numeric conversion, silently missing
   for non-numeric. Was LexError: unexpected character '?'. `?` skips the message,
   `??` also skips _ERROR_; opensas input() is silent-missing regardless. */
data _null_;
  a = input("5", ?? best.);
  b = input("NOTDONE", ?? best.);
  c = input("7", ? best.);
  d = input("3.14", ?? 8.2);
  e = input("<5", ?? best.);
  put a= b= c= d= e=;
run;
