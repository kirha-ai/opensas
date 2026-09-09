/* GAP-inputeofdegrade (part 2/3) — a RECORD ADVANCE past EOF ends the step; it
   does not silently re-read the current record.

   SAS 9.4 DATA Step Statements ref printed p.178 (pdf 189; that page's OWN
   footer reads "178 Chapter 2 / Dictionary of SAS DATA Step Statements"), the
   INPUT statement's "End-of-File" section:
       End-of-file occurs when an INPUT statement reaches the end of the data.
       If a DATA step tries to read another record after it reaches an
       end-of-file, then execution stops.

   The step ends AT the INPUT statement, so nothing after it runs and the
   implicit OUTPUT never fires — no observation, partial or otherwise. That is
   documented by a worked example rather than inferred: printed p.323 (footer
   "RETAIN Statement 323") puts a PUT on EACH SIDE of an INPUT over two data
   lines and reports "The first PUT statement is executed three times, whereas
   the second PUT statement is executed only twice. The DATA step ceases
   execution when the INPUT statement executes for the third time and reaches
   the end of the file." The trailing PUT running one time FEWER is the proof.

   WHAT WAS WRONG: three copies of `if (li + 1 < lines.len) li += 1;` silently
   declined to advance and read on against the SAME record. So `input x $ / y $;`
   over an ODD number of records handed y the value already sitting in x — a
   FABRICATED value, at exit 0.
   expect-rc: 0 */

/* 1 — the fabrication itself. THREE records, two consumed per iteration, so
   iteration 2 reads x=r3 and its `/` asks for a 4th record. Exactly ONE
   observation may be written. It used to write a second one with y=r3 — the
   value re-read out of x, which is the whole defect: not a missing value, a
   DUPLICATE of a real one, indistinguishable from data. */
data one;
  infile datalines;
  input x $ / y $;
  put "1 iter x=" x " y=" y;
  datalines;
r1
r2
r3
;
run;
proc print data=one noobs; title "1 one obs; NO r3/r3 row"; run;

/* 2 — the PUT above fires ONCE, not twice: p.323's evidence reproduced. A
   diagnostic-only fix would still have run the body a second time. */

/* 3 — `#n` is the other advance spelling and stops the same way. #2 on a
   one-record file asks for a record that is not there. */
data hn;
  infile datalines;
  input #1 a $ #2 b $;
  put "3 iter a=" a " b=" b;
  datalines;
solo
;
run;
proc print data=hn noobs; title "3 #2 past EOF: no obs"; run;

/* 4 — DLM= reads go through a SEPARATE record scanner (io.readDelim) that had
   its OWN copy of the same pattern — the producer the ticket did not name. Same
   shape, same fix, and without it this case still fabricated. */
data dl;
  infile datalines dlm=',';
  input p $ / q $;
  put "4 iter p=" p " q=" q;
  datalines;
a,b
c,d
e,f
;
run;
proc print data=dl noobs; title "4 dlm= advance past EOF: one obs"; run;

/* 4b — DLM= with `#n`, the FIFTH guard. Added because mutation testing found it
   had ZERO coverage: deleting that guard left the whole 1842-case suite GREEN,
   because nothing anywhere combined a delimited read with a `#n` past the end.
   A guard the suite cannot see is not protecting anything. */
data dh;
  infile datalines dlm=',';
  input #1 m $ #2 n $;
  put "4b iter m=" m " n=" n;
  datalines;
a,b
;
run;
proc print data=dh noobs; title "4b dlm= #2 past EOF: no obs"; run;

/* 5 — CONTROL: an EVEN record count is fully satisfied and must be untouched.
   Four records, two per iteration, two observations, no stop. */
data even;
  infile datalines;
  input x $ / y $;
  datalines;
r1
r2
r3
r4
;
run;
proc print data=even noobs; title "5 even count: two obs, unchanged"; run;

/* 6 — CONTROL: short-record handling is a DIFFERENT rule and stays. Under
   TRUNCOVER the advance still works (that is BUG-inputmultirecmode) and a short
   record still yields missing without spilling — only the advance PAST THE END
   stops. */
data tc;
  infile datalines truncover;
  input a $ / b $ c $;
  datalines;
A
B
;
run;
proc print data=tc noobs; title "6 truncover short record: c missing, obs kept"; run;
