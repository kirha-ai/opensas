/* GAP-sqlspantailguard — WHERE tail guard.

   `pe.Parser.parseExpr` consumes one expression and leaves the cursor on the
   first token it cannot use. Without a whole-span guard, `where name ? 'ap'`
   silently truncated to `where name`, which is not the program the user wrote.
   `?` is the documented CONTAINS alias, but opensas does not implement it, so
   this is an opensas gap (rc 2), not a user syntax error. The clean CONTAINS
   query proves the interpreter reached the SQL path and fixes the golden stdout.
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
