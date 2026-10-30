/* GAP-sqlspantailguard — WHERE tail guard.

   `pe.Parser.parseExpr` consumes one expression and leaves the cursor on the
   first token it cannot use. Without a whole-span guard, unsupported tails could
   silently truncate a predicate, which is not the program the user wrote. `?`
   is the documented CONTAINS alias; GAP-sqlcontainsquestion implements it, so
   the alias query must match spelled-out CONTAINS. The final `@` is a lexer
   token the SQL expression parser cannot consume; refusing it pins the guard.
   expect-rc: 2 */

data t;
  length name $8;
  input name $;
  datalines;
apple
berry
;
run;

proc sql;
  title 'where_contains_word';
  select name from t where name contains 'ap';
quit;

proc sql;
  title 'where_contains_alias';
  select name from t where name ? 'ap';
quit;

proc sql;
  select name from t where name @ 'ap';
quit;
