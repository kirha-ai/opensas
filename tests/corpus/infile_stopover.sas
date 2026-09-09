/* GAP-inputlow-tick287 F12: STOPOVER is the fourth INFILE record-end mode
   (FLOWOVER default / MISSOVER / TRUNCOVER / STOPOVER, Statements: INFILE).
   The EBNF marked all four honored, but STOPOVER was the lone mode with NO
   fixture — the Phase-G blind spot cutting in the marked direction. A short
   record under STOPOVER is a DATA error in real SAS too: loud ERROR, rc 1
   (D-009: the user's data is short — not an opensas gap, so not rc 2).
   Step 1 is the FLOWOVER control (INPUT crosses the record boundary, one obs).
   Step 2 must ERROR on the short record and exit 1 — if STOPOVER silently
   regresses to FLOWOVER/MISSOVER, the run completes rc 0 with a second
   "stop" line and BOTH golden and rc mismatch.
   NOTE: the golden holds only the FLOWOVER control line — on the exec-error
   path opensas currently drops the step's buffered PUT output (side finding
   reported under GAP-inputlow-tick287; flush site is main.zig/exec.zig, not
   this ticket's files). When that lands, step 2's completed first obs
   ("stop x=1 y=2") appears here.
   expect-rc: 1 */
data _null_;
  infile datalines flowover;
  input x y;
  put 'flow ' x= y=;
datalines;
1
2
;
run;

data _null_;
  infile datalines stopover;
  input x y;
  put 'stop ' x= y=;
datalines;
1 2
3
;
run;
