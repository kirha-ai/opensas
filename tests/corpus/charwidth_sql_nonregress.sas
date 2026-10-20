/* EPIC-charfixedwidth-slice1 (GH#27) probe-C NON-REGRESSION pin: SQL
   computed character values are FULL-LENGTH today and must STAY full-length.
   The broad width-on-first-assign attempt was REVERTED for truncating
   exactly this class — SQL CASE 'small'->'sma', function results
   'banana'->'banan', 'CARDIAC DISORDERS'->'DISOR' — data loss. The literal-
   RHS width stamp lives ONLY in the DATA-step assignment arm and the
   retain-init path (exec.zig store sites with the AST in hand); PROC SQL's
   computed columns bind their own widths (sql.zig bindCol) and never pass
   those sites, so nothing here may shift. Every value, LENGTH(), and
   VLENGTH() below is the PRE-slice behavior — this fixture exists to go RED
   the moment a future width change reaches a computed context.
   (no PHI) */
data one;
  x = 1;
run;

proc sql;
  create table sq as
  select case when 0 then 'ab' else 'abcdef' end as c1,
         upcase('small') as c2,
         cats('CARDIAC',' DISORDERS') as c3
  from one;
quit;

data chk;
  set sq;
  l1 = length(c1);
  l2 = length(c2);
  l3 = length(c3);
  w1 = vlength(c1);
  w2 = vlength(c2);
  w3 = vlength(c3);
run;
proc print data=chk noobs; run;
