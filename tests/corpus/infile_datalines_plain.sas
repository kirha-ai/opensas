/* BUG-infiledatalines: `infile datalines;` with NO trailing options (DLM/DSD/…)
   was mis-lexed — the lexer entered raw-line capture on any `datalines;` and
   swallowed the rest of the step (ParseError "expected a statement"). A datalines
   STATEMENT begins a statement (prev token `;`); the INFILE-device form is
   preceded by `infile`, so only the statement form should trigger raw capture.
   Guard: a normal `datalines;` block still reads correctly. */
data plain;
  infile datalines;
  input a b c;
  datalines;
1 2 3
4 5 6
;
run;
proc print data=plain; run;
data normal;
  input x y $;
  datalines;
10 aa
20 bb
;
run;
proc print data=normal; run;
