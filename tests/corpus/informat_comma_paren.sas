/* BUG-commaparen: the COMMA/DOLLAR informats read parentheses as a NEGATIVE
   value — `(1,234)` -> -1234 (Language Reference: Concepts "Reading Nonstandard Numeric Data": parens
   require the COMMA informat; leading paren = minus sign). Was silently read as
   missing. Covers all three read paths: input() function, INPUT statement, and
   the plain `w.` guard (parens are invalid there -> missing, per SAS). */
data _null_;
  a = input('($1,234)', dollar12.);
  b = input('(1,234.5)', comma12.1);
  c = input('-45', comma8.);
  p = input('(5)', 8.);        /* plain w.: parens invalid -> missing */
  put a= b= c= p=;
run;
data _null_;
  input x comma8.;
  put x=;
  datalines;
(500)
;
run;
