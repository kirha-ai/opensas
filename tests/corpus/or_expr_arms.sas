/* EBNF-gate tick356 marker evidence — or_expr arms "|" | "!" | "¦" | "OR"
   (Language Reference: Concepts Table 6.6 Group VII): `!` and `¦` lex to the pipe token (fixture
   expr_alt_ops landed that), the word OR shares the arm; chained spellings mix
   and OR binds looser than AND (Group VI). */
data _null_;
  a = (1 | 0);  b = (0 ! 0);  c = (0 ¦ 0);  d = (0 OR 0);
  e = (1 ! 0 ¦ 0 | 0 OR 0);   /* chained across spellings */
  f = (1 OR 1 AND 0);         /* AND binds tighter -> 1 OR 0 -> 1 */
  put a= b= c= d= e= f=;
  if 0 ! 0 then put "BAD"; else put "bang-false ok";
  if 1 ¦ 0 then put "bb-true ok";
run;
