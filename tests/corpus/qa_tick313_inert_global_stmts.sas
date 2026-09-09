/* QA tick312 F1 / BUG-inertglobalstmts — POSITIVE CONTROL: every log-only /
   session-only SAS 9.4 global statement, each placed BETWEEN two working
   steps. Real SAS accepts all of these silently; a batch interpreter cannot
   observe any of them (opensas renders no SAS log, no graphics, one session).
   The pre-fix regression hard-ERRORed each one, and because a step ERROR trips
   syntax-check mode, ONE of these statements truncated every LATER step — the
   second PROC PRINT below is the output that matters (exit 0, both tables).
   Doc: Language Reference: Concepts p.209 (PAGE "skips to a new page in the SAS log", SKIP "skips a
   specified number of lines in the SAS log"), Language Reference: Concepts p.181 (CHECKPOINT
   EXECUTE_ALWAYS is a no-op unless checkpoint mode is on), SAS Global
   Statements: Reference (RESETLINE/SYSECHO same log family; LOCK always
   grantable single-session), SAS/GRAPH family of the already-inert GOPTIONS
   (AXIS/LEGEND/PATTERN/SYMBOL). MISSING stays loud on purpose (Language Reference: Concepts p.106 —
   it changes INPUT decoding, so it is result-changing, not inert). */
data d; x=1; run;
page;
skip 2;
resetline;
sysecho 'checkpoint one';
checkpoint execute_always;
lock work.d;
lock work.d clear;
goptions reset=all;
sasfile work.d load;
catname cathere;
dm 'log;clear';
axis1 c=blue;
legend1 position=(bottom right);
pattern1 v=s;
symbol1 v=dot;
run;
quit;
proc print data=d noobs; run;
data e; y=2; run;
proc print data=e noobs; run;
