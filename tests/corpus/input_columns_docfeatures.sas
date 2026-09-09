/* Column input's documented feature list — SAS 9.4 Language Reference: Concepts
   p.514 (PDF 532), "Column Input":
     - "Input values can be read in any order, regardless of their position in
       the record."
     - "Values or parts of values can be reread."
     - "Placeholders, such as a single period (.), are not required for missing
       data."  (and p.519: "All input styles except list input also allow a
       blank to represent a missing numeric value.")
     - "Both leading and trailing blanks within the field are ignored."
     - "Character values can contain embedded blanks."
   input_columns/input_colrange_cursor pin left-to-right ranges and the cursor;
   the out-of-order, reread and blank-field rules were un-pinned. */

/* out-of-order (b read before a) + reread (aa re-reads part of a's field) */
data _null_;
  infile datalines truncover;
  input b 5-8 a 1-3 aa 1-2;
  put "a=" a " b=" b " aa=" aa;
datalines;
123 4567
;
run;

/* an all-blank numeric field is missing — no period needed, no error */
data _null_;
  infile datalines truncover;
  input x 1-3 y 5-7;
  put "x=" x " y=" y;
datalines;
111 222
333
;
run;

/* leading/trailing blanks inside the field are ignored; a character field keeps
   its embedded blanks */
data _null_;
  infile datalines truncover;
  input n 1-6 nm $ 7-19;
  put "n=" n " nm=[" nm "]";
datalines;
   42 John  Smith
;
run;
