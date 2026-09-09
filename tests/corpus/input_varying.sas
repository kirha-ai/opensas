/* BUG-varyinginformat: `input var $VARYINGw. length-variable;` — the token after
   the $VARYING informat is NOT a second input variable, it is the LENGTH-VARIABLE
   operand giving the field width (0..w) to read for `var` at the current column
   pointer. opensas used to parse it as a second variable, reading `var` at a fixed
   width and consuming the length-var as data (silent wrong). SAS: read min(len,w)
   cols, advance the pointer by that many; len<=0/missing -> read no data. */

/* 1. finding repro: len=3 assigned before INPUT, read 3 of 8 columns */
data _null_;
  length name $20;
  len = 3;
  input name $varying10. len;
  put "name=" name "| len=" len;
datalines;
abcdefgh
;
run;

/* 2. missing length -> read no data, name stays blank, len preserved */
data _null_;
  length name $20;
  len = .;
  input name $varying10. len;
  put "name=" name "| len=" len;
datalines;
abcdefgh
;
run;

/* 3. width varies per record; the length is read from a prior line, then a
      trailing field must resume from the column just past the varying field.
      len=0 -> no data read AND the pointer does not advance (tail sees col 1). */
data _null_;
  length name $20 tail $10;
  input len 2. / name $varying20. len tail $;
  put "len=" len " name=" name " tail=" tail;
datalines;
03
abcXYZ
05
abcdeXYZ
00
abcXYZ
;
run;
