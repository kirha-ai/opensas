/* BUG-sqlremergecharcol — a CHARACTER computed column keeps its type when it
   stands next to an aggregate.

   execGrouped and execRemerge must DECLARE their output columns before the row
   loop (that loop resolves `calculated <alias>` by name out of the column list),
   so at declaration time no value exists yet and an expression column was typed
   NUMERIC outright. A char expression beside an aggregate — `select upcase(b) as
   ub, max(b) as mb` — therefore landed in a Num column while its cells stayed
   character.

   Only the DESCRIPTOR was wrong, which is why a green listing hid it: PROC SQL
   prints the cell, so the text still appeared. The damage was downstream —
     CONTENTS said `ub Num 8`
     a DATA step `set` read 'AB' as numeric MISSING (the value destroyed)
     a nested SELECT re-rendered it BEST12, so lengthc(ub) was 12
     `having <char computed alias>` silently filtered NOTHING
   The type now follows the value the expression produced, which is the same
   evidence the no-aggregate path (execRowWise) already used inline — so all
   three paths agree rather than there being a fourth rule.

   No doc citation is needed or offered for a WIDTH here: a computed column's
   width stays DOC-SILENT (BUG-sqlcolwidthloss) and keeps the value width. The
   TYPE is not a doc question at all — a character expression yields a character
   column, and the descriptor must not disagree with the cell it describes. */

data src;
  length b $4 v 8;
  b='AB'; v=1; output;
  b='CD'; v=2; output;
run;

/* ── remerge (aggregate + detail column, no GROUP BY) ──────────────────── */
proc sql;
  select upcase(b) as ub, max(v) as mv from src;
  create table r_re as select upcase(b) as ub, max(v) as mv from src;
quit;
proc contents data=r_re; run;
data _null_; set r_re;
  l=lengthc(ub);
  put 'REMERGE set ub=[' ub '] lengthc=' l;
run;

/* ── grouped (aggregate + GROUP BY) ────────────────────────────────────── */
proc sql;
  select b, upcase(b) as ub, max(v) as mv from src group by b;
  create table r_gr as select b, upcase(b) as ub, max(v) as mv from src group by b;
quit;
proc contents data=r_gr; run;
data _null_; set r_gr;
  l=lengthc(ub);
  put 'GROUPED set ub=[' ub '] lengthc=' l;
run;

/* ── CONTROL: the same expression with NO aggregate was always right ───── */
proc sql;
  create table r_plain as select upcase(b) as ub from src;
quit;
proc contents data=r_plain; run;

/* ── the nested-SELECT shape that rendered BEST12 ──────────────────────── */
proc sql;
  select lengthc(ub) as l from (select upcase(b) as ub, max(v) as mv from src);
quit;

/* ── HAVING on a computed alias: the char arms used to filter nothing ──── */
proc sql;
  title 'having char alias, remerge — one row';
  select upcase(b) as ub, max(v) as mv from src having ub='AB';
  title 'having char alias, grouped — one row';
  select b, upcase(b) as ub, max(v) as mv from src group by b having ub='CD';
  title 'control: having numeric computed alias';
  select b, v*10 as vv, max(v) as mv from src group by b having vv>10;
  title 'control: having aggregate alias';
  select b, max(v) as mv from src group by b having mv>1;
  title 'control: having char CASE alias (caseResultType already typed it char)';
  select b, case when v=1 then 'one' else 'two' end as w, max(v) as mv
    from src group by b having w='one';
quit;
title;

/* ── CONTROL: a NUMERIC computed column beside an aggregate stays Num ──── */
proc sql;
  create table r_num as select v*10 as vv, max(v) as mv from src;
quit;
proc contents data=r_num; run;
data _null_; set r_num;
  put 'NUMERIC set vv=' vv ' mv=' mv;
run;
