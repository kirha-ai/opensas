/* BUG-specialmiss-afterkw: a special-missing literal (.a-.z/._) must lex as ONE
   token after a value-EXPECTING keyword operator (if/and/to/...), not split into
   `.` + name. Previously `if .a < .z then` errored "expected ';' or 'then'". */
data _null_;
  /* leads with special-missing right after `if` and after word-op `and` */
  if .a < .z then put "kw_if_ok";
  b = .b;
  if b and 1 then put "b_is_missing_falsy";  /* .b is missing -> falsy, no print */
  if .a <= .a then put "kw_le_ok";
  /* regression guards: value-position special missing already worked */
  x = .a;      put "assign=" x=;
  p = .a + 1;  put "expr=" p=;
  q = .a;      if q = .a then put "cmp_ok";
run;
