/* BUG-prxmatchpad (GH#28): the SUBJECT of a PRX function is a bare char
   VARIABLE read PADDED to its declared width — fixed-width storage semantics,
   the same rule `||` already applies (BUG-concatnopad; Language Reference:
   Concepts p.49). With `length s $8; s="abc"` the subject is "abc"+5 blanks, so
   /abc$/ and /^abc$/ FAIL in live SAS 9.4; a literal subject, a no-anchor
   pattern and the trim() idiom are unchanged; real blanks stay a no-match
   control. lengthc/length 8/3 pin that only the SUBJECT read changed —
   storage stays unpadded (EPIC-charfixedwidth). */
data _null_;
  length s $8;
  s = "abc";
  m1 = prxmatch('/abc$/', s);       /* padded -> $ fails -> 0 (was the bug) */
  m2 = prxmatch('/^abc$/', s);      /* both anchors -> 0                   */
  m3 = prxmatch('/abc$/', "abc");   /* literal subject unpadded -> 1       */
  m4 = prxmatch('/abc/', s);        /* no anchor -> 1                      */
  mt = prxmatch('/abc$/', trim(s)); /* computed expr unpadded -> 1         */
  s2 = "abc     ";                  /* real blanks, full 8-byte value      */
  m5 = prxmatch('/abc$/', s2);      /* control: 0 before and after         */
  lc = lengthc(s); l = length(s);   /* 8 / 3: width tracked, value short   */
  put "anchor=" m1 " both=" m2 " literal=" m3 " noanchor=" m4;
  put "trim=" mt " blanks=" m5 " lengthc=" lc " length=" l;
run;
