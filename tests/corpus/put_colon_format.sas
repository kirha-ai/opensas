/* GAP-putcolonformat — the PUT `:` MODIFIED LIST OUTPUT modifier.

   SAS 9.4 DATA Step Statements ref, "PUT Statement: List". Printed p.297 gives
   the syntax slot:
       PUT <pointer-control> variable < : | ~> format.<@ | @@>;
   Printed p.298 (pdf 309; that page's OWN footer reads "298 Chapter 2 /
   Dictionary of SAS DATA Step Statements") defines it:
       :  enables you to specify a format that the PUT statement uses to write
          the variable value. All leading and trailing blanks are deleted, and
          each value is followed by a single blank.

   NOT the INPUT statement's colon. INPUT's (printed p.193) governs WHERE
   READING STOPS — "reads the value from the next non-blank column until the
   pointer reaches the next blank column" — while PUT's governs blank-stripping
   on OUTPUT. The volumes never cross-reference the two: each `:` entry "See"s
   only its own side's details section. Structurally parallel, semantically
   unrelated, and conflating them would have produced a different renderer.

   THE EXPECTED OUTPUT BELOW IS THE DOC'S OWN, not opensas's. Printed p.299
   ("How Modified List Output and Formatted Output Differ") prints both halves
   of blocks 1 and 2 verbatim, and printed p.44 prints block 3's. That makes
   this fixture a transcription of the reference rather than a snapshot of us.
   expect-rc: 0 */

/* ---- 1: printed p.299's modified-list program, and its printed log ----
   doc:  2,353.20 7.10
         6,231.00 121.00                                              */
data _null_;
  input x y;
  put x : comma10.2 y : 7.2;
  datalines;
2353.20 7.10
6231 121
;
run;

/* ---- 2: printed p.299's FORMATTED contrast, unchanged by this work. The
   pointer moves the length of the format, so the values line up in columns.
   This is the control: the colon must not leak into plain formatted output.
   doc:    2,353.20   7.10
           6,231.00 121.00                                            */
data _null_;
  input x y;
  put x comma10.2 y 7.2;
  datalines;
2353.20 7.10
6231 121
;
run;

/* ---- 3: printed p.44 (BY Statement Example 4) — the NO-SPACE spelling
   `height:best12.`, on a variable that already carries an attached format the
   modifier overrides for that one term. 72 prints bare, 51.3 is not padded
   to width 12.
   doc:  Shortest in Under 55 measures 51.3
         Shortest in Over 70 measures 72                              */
data _null_;
  format h range8.2;
  h = 51.3; put 'Shortest in Under 55 measures ' h:best12.;
  h = 72;   put 'Shortest in Over 70 measures ' h:best12.;
run;

/* ---- 4: the two halves of the definition, isolated ----
   LEADING blanks deleted: a right-aligned numeric format pads on the left,
   and the modifier removes that padding.  TRAILING blanks deleted: $char8.
   pads a short string on the right.  Brackets make both edges visible. */
data _null_;
  n = 42; c = 'ab';
  put '[' n 8. ']';        /* formatted: keeps the width      */
  put '[' n : 8. ']';      /* modified list: leading gone     */
  put '[' c $char8. ']';   /* formatted: keeps the width      */
  put '[' c : $char8. ']'; /* modified list: trailing gone    */
run;

/* ---- 5: "each value is followed by a single blank" — the separator rule.
   A modified-list item spaces like a LIST item, not like a formatted one, so
   consecutive items get exactly one blank between them and a following
   literal gets one too (that trailing blank is what p.283's `+(-1)` exists to
   take back before a period). */
data _null_;
  a = 1; b = 2;
  put a : 4. b : 4. 'end';
run;

/* ---- 6: a character value whose stored width exceeds the format, plus a
   missing numeric — the modifier must not invent or swallow content. */
data _null_;
  length s $10;
  s = 'hi';
  m = .;
  put '<' s : $4. '>' m : 6.2 '<';
run;
