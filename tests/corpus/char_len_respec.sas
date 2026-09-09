/* BUG-charlenrespec (doc-finder tick272 F3): a SECOND character-length spec
   for the same var is IGNORED — SAS keeps the FIRST length and warns (Language Reference: Concepts
   p.49: "You cannot change the length of a character variable with a
   subsequent LENGTH or ATTRIB statement within the same DATA step"). The
   WARNING lands on stderr; stdout below pins that the descriptor length
   (VLENGTH) and the STORED value agree — case c used to disagree (descriptor
   20 but value truncated at 5). First-wins covers LENGTH↔LENGTH,
   LENGTH↔ATTRIB, and ATTRIB↔LENGTH.

   Positive controls: a var declared with ONE consistent char length still
   truncates/stores exactly as before (no spurious warning, no length change). */

/* case a: LENGTH then LENGTH — first (20) wins, value full */
data a; length x $20; length x $5; x='abcdefghij'; run;
data _null_; set a; n=vlength(x); put "a vlen=" n " x=[" x "]"; run;

/* case b: LENGTH then ATTRIB length= — first (20) wins */
data b; length x $20; attrib x length=$5; x='abcdefghij'; run;
data _null_; set b; n=vlength(x); put "b vlen=" n " x=[" x "]"; run;

/* case c: ATTRIB length= then LENGTH — first (5) wins, descriptor == value */
data c; attrib x length=$5; length x $20; x='abcdefghij'; run;
data _null_; set c; n=vlength(x); put "c vlen=" n " x=[" x "]"; run;

/* positive: single consistent char length — truncates at 5, no warning */
data p; length y $5; y='abcdefghij'; run;
data _null_; set p; n=vlength(y); put "p vlen=" n " y=[" y "]"; run;
