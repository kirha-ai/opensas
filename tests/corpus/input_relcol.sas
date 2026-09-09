/* BUG-inputrelcol: the relative column pointer `+n` after a token/fixed read must
   land on the right columns. Root cause: `col` and the tokenizer byte cursor were
   tracked independently, so a `+n` after a fixed/list read pointed at the wrong
   place (silent wrong data). `@n` (absolute) masked it. All three cases assert
   against real SAS 9.4. */

/* 1. the ticket repro: fixed read, then +1, then a formatted numeric */
data _null_;
  input x $4. +1 y 3.;
  put "x=" x " y=" y;
datalines;
abcd 123
;
run;

/* 2. mixed fixed / +n / @n:
      name cols 1-4, skip 2 (+2 -> col 7), age cols 7-8, @9, code cols 9-11 */
data _null_;
  input name $4. +2 age 2. @9 code 3.;
  put "name=" name " age=" age " code=" code;
datalines;
Mary  30777
;
run;

/* 3. pure relative pointer off a LIST-input token: st reads "NY" (pointer at
      col 3), +3 -> col 6, rest reads 5 cols from col 6 = "345" */
data _null_;
  input st $ +3 rest $5.;
  put "st=" st " rest=" rest;
datalines;
NY 12345
;
run;
