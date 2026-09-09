/* ATTRIB-length-compact — premise-audit pin. The ticket claimed:
   "`attrib c length=$n; c = num;` stores COMPACT (ATTRIB length not
   parser-tracked, so the `__assignc` BESTn desugar doesn't fire;
   parser.zig:452 only sees LENGTH-stmt lengths)".
   Verdict: DOES NOT REPRODUCE — both spellings store Char 8 and print
   identically. ATTRIB length= has fed the parser's char_lens since
   parseAttrib was born (6cfc43b3, G-ebnf10), weeks before the ticket
   was filed (tick-103); 444f6c50 probed innocent (parent identical).
   This fixture pins the two spellings side by side so a future
   regression that splits them turns red here. */
data t;
  n = 5;
  attrib c length=$8;
  c = n;
  length d $8;
  d = n;
run;
proc contents data=t; run;
proc print data=t; run;
