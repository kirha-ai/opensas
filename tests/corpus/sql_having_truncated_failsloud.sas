/* GAP-sqlspantailguard — HAVING tail guard.

   HAVING runs through the same expression parser contract as JOIN ON and WHERE:
   an unsupported tail can be left unread with no parser error. Guard the whole
   HAVING span so unsupported tails do not evaluate a truncated predicate. `?`
   is legal SAS as the CONTAINS alias; GAP-sqlcontainsquestion implements it, so
   the alias query must match spelled-out CONTAINS. */

data t;
  length name $8;
  input name $;
  datalines;
apple
berry
;
run;

proc sql;
  title 'having_contains_word';
  select name from t having name contains 'ap';
quit;

proc sql;
  title 'having_contains_alias';
  select name from t having name ? 'ap';
quit;
