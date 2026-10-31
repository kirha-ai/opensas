/* GAP-macrooptfamily — HONOURED: an OPTIONS-set SASAUTOS feeds the autocall
   engine (Macro Ref ch.20 p.482). Until now only --sasautos/$SASAUTOS could
   reach it, so `options sasautos=...` in a program was rc 1 "not recognized"
   AND errhalt-skipped the rest of the run (the MED run-killer shape).
   Pins, in output order:
     - the FIRST listed location wins (p.482: "opens and searches each
       location in the same order"): greet exists in tests/autocall2 AND
       tests/autocall — DIR2 answers;
     - a macro the first dir lacks (shout) still resolves from the second;
     - NOMAUTOSOURCE suspends the search: whisper is NOT yet compiled there,
       so %whisper(C) is dropped (its "apparent invocation" WARNING is log
       output, not stdout) and NO psst-C line reaches the listing;
     - MAUTOSOURCE resumes it: whisper resolves on the next try.
   MCOMPILENOTE=ALL (ch.20 p.454) rides along: the compile NOTEs go to the
   log, so the listing diff stays pure. */
options mautosource sasautos=('tests/autocall2', 'tests/autocall') mcompilenote=all;
%greet(A)
%shout(B)
options nomautosource;
%whisper(C)
options mautosource;
%whisper(D)
data _null_; put "END"; run;
