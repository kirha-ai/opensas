/* BUG-inputatvarptr: INPUT `@n` column pointer — numeric-literal AND variable
   operand. A `@` followed by a number or a variable NAME is a COLUMN POINTER
   (move the input pointer to column n before the next read); a trailing `@`
   with NO operand is the line-hold. Previously `@var` was mis-parsed as a
   trailing-@ hold plus a list read of the variable (n overwritten, x missing). */
data literal;
  input @3 x 2.;
  put "x=" x;
datalines;
AB12
;
run;

data varptr;
  retain n 5;
  input @n x 2.;
  put "n=" n "| x=" x;
datalines;
    12
;
run;

data between;
  input name $ @11 age 2.;
  put "name=" name "| age=" age;
datalines;
Bob       42
;
run;
