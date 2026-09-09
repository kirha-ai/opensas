/* NOTE-sqltruncblanks: the DATA step and PROC SQL truncate string comparisons
   by DIFFERENT rules, and the SQL Procedure User's Guide states both in one
   sentence, printed p.405, assigning each to its surface:

     "The Base SAS WHERE processor truncates comparisons based on the ACTUAL
      LENGTH of a string, EVEN IF A STRING INCLUDES BLANKS AT THE END. PROC SQL
      TRIMS TRAILING BLANKS from the string values before it truncates
      comparisons."

   So the DATA step's `=:` family keeps the storage-length rule (LENGTHC) —
   that half was already conformant and must not move — while PROC SQL's
   EQT/GTT/LTT/GET/LET/NET trim first, which is LENGTHN.

   The two only disagree when the SHORTER operand carries trailing blanks, so
   that is what this fixture pins, on both surfaces at once:
     'ABC' vs 'AB  '   DATA =:  -> min(lengthc)=3 -> 'ABC' vs 'AB ' -> 0
                       SQL  eqt -> min(lengthn)=2 -> 'AB'  vs 'AB'  -> 1
   Every other row is a control that must read the SAME on both surfaces. */
data t;
  length a $3 b $4;
  a='ABC'; b='AB'; output;
run;

data _null_;
  /* DATA step: the storage-length rule, trailing blanks INCLUDED */
  blanks = ('ABC' =: 'AB  ');   /* 0 — the shorter operand's blanks count */
  plain  = ('ABC' =: 'AB');     /* 1 — no trailing blanks, rules agree */
  gt     = ('ABC' >: 'AB  ');
  ne     = ('ABC' ^=: 'AB  ');
  put 'DATA eq blanks = ' blanks;
  put 'DATA eq plain  = ' plain;
  put 'DATA gt blanks = ' gt;
  put 'DATA ne blanks = ' ne;
run;

proc sql;
  /* PROC SQL: trailing blanks TRIMMED before truncating */
  select count(*) as sql_eq_blanks from t where a eqt 'AB  ';
  select count(*) as sql_eq_plain  from t where a eqt 'AB';
  select count(*) as sql_ne_blanks from t where a net 'AB  ';
  select count(*) as sql_ge_blanks from t where a get 'AB  ';
  /* an operand with NO trailing blanks is unaffected by the rule change */
  select count(*) as sql_lt_plain  from t where a ltt 'B';
quit;
