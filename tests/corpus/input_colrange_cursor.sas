/* BUG-inputcolrangecursor: a column-range read (`var s-e`) never advanced the
   read cursor, so the NEXT variable (list / +n / formatted) silently re-read
   the range's columns. Control: two absolute ranges in a row were already fine
   and must stay byte-identical. */

/* 1. the ticket repro: range, then a list var — name must read ABC, not 001 */
data _null_;
  input id 1-3 name $;
  put "id=" id " name=" name;
datalines;
001 ABC
;
run;

/* 2. range, then +n relative pointer: id cols 1-3 (cursor col 4), +1 -> col 5,
      code reads 3 cols from col 5 = "XYZ" */
data _null_;
  input id 1-3 +1 code $3.;
  put "id=" id " code=" code;
datalines;
001 XYZ99
;
run;

/* 3. control: all absolute ranges — cursor-independent, output unchanged */
data _null_;
  input a 1-3 b $ 5-7;
  put "a=" a " b=" b;
datalines;
001 ABC
;
run;
