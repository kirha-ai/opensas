/* BUG-lengthaftersetinput (QA tick356 F3): Language Reference: Concepts p.49 note 1 — "You cannot
   change the length of a character variable with a subsequent LENGTH or ATTRIB
   statement within the same DATA step." All three establishment paths pinned
   side by side so they can never silently disagree again: a char LENGTH/ATTRIB
   placed AFTER the statement that established the variable is IGNORED (the
   first length stands — no truncation) and warns; stdout below pins the data.
   The warning arms fire in src/main.zig's test block (captured diags).
   Controls: a NEW var declared after SET/INPUT still gets its declared length,
   and a LENGTH placed FIRST still pins the schema (before-set truncates). */
data a; length s $10; s='abcdefghij'; run;

data b; set a;  length s $3;        put "after-set    s=[" s "]"; run;
data b2; set a; attrib s length=$3; put "after-set-at s=[" s "]"; run;

data c; input s $10.; length s $3;  put "after-input  s=[" s "]";
datalines;
abcdefghij
;
run;
data c2; input s $10.; attrib s length=$3; put "after-inp-at s=[" s "]";
datalines;
abcdefghij
;
run;

data d; s='abcdefghij'; length s $3;         put "after-assign s=[" s "]"; run;
data d2; s='abcdefghij'; attrib s length=$3; put "after-asn-at s=[" s "]"; run;

/* controls: brand-new vars after SET / INPUT are still declared at their
   length (no warning, no first-wins), and LENGTH-first still pins ($3). */
data e; set a; length newv $3; newv='xyz'; put "new-after-set   newv=[" newv "] s=[" s "]"; run;
data f; input s $10.; length newv $3; newv='xyz'; put "new-after-input newv=[" newv "]";
datalines;
abcdefghij
;
run;
data g; length s $3; set a; put "before-set   s=[" s "]"; run;
