/* GAP-varcolonprefix: a VAR prefix that matches NO column. The doc (Language Reference: Concepts
   printed p.70 Table 4.5) settles only the matching rule, not the empty
   case — so GAP-ofcolonprefix's empty-match arm is the precedent and both
   sites now agree: a typo'd prefix is the user's error (D-009), the SAME
   loud rc-1 "Variable X not found." an unknown name gets (D-002), never a
   silent zero-column report.
   expect-rc: 1 */
data t;
  x1 = 1; y = 2;
run;
proc print data=t;
  var zz:;
run;
