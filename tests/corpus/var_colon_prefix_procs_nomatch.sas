/* GAP-varcolonprefix-procs: a prefix that matches NO column is the SAME
   loud rc-1 ERROR the OF (eval.zig: "the name prefix '{s}' matched no
   variables") and PRINT (main.zig: "Variable X not found.") expansion arms
   already emit — a third disagreeing empty-match behaviour would replace
   one inconsistency with another. The doc (Language Reference: Concepts printed p.70 Table 4.5)
   settles only the matching rule; D-002 + the two precedents settle the
   rest: a typo'd prefix is the user's error (D-009), never a silent
   zero-variable analysis.
   expect-rc: 1 */
data t;
  x1 = 1; y = 2;
run;
proc means data=t;
  var zz:;
run;
