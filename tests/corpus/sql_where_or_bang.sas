/* GAP-wherelow-tick291 (A) — PROBE VERDICT: NOT A DEFECT. The board claimed
   `where x=1 ! y=9` was "not even lexed" and feared a SILENTLY WRONG ROW SET;
   probing showed the lexer already aliases `!` to the OR token and every
   WHERE route returns the OR rows. Pinned here so the stale line cannot
   come back.
   Doc: `!` is a legacy OR spelling — DATA Step Statements ref printed
   pp.363-364, the WHERE operator table's footnote 2: "The OR symbol ( | ),
   broken vertical bar ( ¦ ), and exclamation point (!) all indicate a
   logical or"; PROC SQL Table 8.2 group 10 (printed p.404) lists `|, OR`
   and defers alternate symbols to Language Reference: Concepts. expr_alt_ops pins the DATA-step
   spellings; this fixture pins the PROC SQL WHERE row set on a table where
   OR, AND and neither all differ:
     x=1 OR y=9  -> (1,9) (2,9) (1,5)     x=1 AND y=9 -> (1,9) only
   and the precedence arm, where `a OR b AND c` = a OR (b AND c) gives the
   same three rows while (a OR b) AND c would give only (2,9). A
   silent-wrong regression moves this golden.
   expect-rc: 0 */
data t;
  input x y;
  datalines;
1 9
2 9
1 5
4 5
;
run;
proc sql;
  create table o as select x, y from t where x=1 ! y=9;
  create table p as select x, y from t where x=1 ! y=9 and x=2;
quit;
data _null_; set o; put x= y=; run;
data _null_; set p; put "prec " x= y=; run;
