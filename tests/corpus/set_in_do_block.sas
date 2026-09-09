/* BUG-doblocksourceinert (QA tick307 F1, HIGH regression): a SET inside a
   `do … end` block was COMPLETELY INERT — collectExtraSetsStmt was the only
   statement walker in exec.zig with no .do_ arm (findSetStmt, scan,
   declareStmt, collectHashTargets, uninitScanStmt all have one), so the block
   swallowed the source: zero rows read, ONE fabricated all-missing
   observation, exit 0, no diagnostic. Landings 2/3/5 of the nested-source
   series restored the driver/read/schema for the .if_ arm only; the .do_
   block got none, and zero corpus fixtures used the shape — which is why six
   individually-green gates missed it. The block form must read exactly like
   the pinned `if 1 then set a;` sibling (set_nested_opts). */
data a; input k v; datalines;
1 10
2 20
;
run;

/* SET in a non-iterative block: reads both rows (was 1 fabricated obs). */
data o1; if 1 then do; set a; end; run;
proc print data=o1 noobs; run;

/* the read fires at the node: statements after it in the block see the row */
data o2; if 1 then do; set a; w = v * 2; end; run;
proc print data=o2 noobs; run;

/* SET with END= inside the block terminates via the extra-set cursor:
   2 obs, e = 0 then 1 — identical to the bare-IF sibling set_nested_opts. */
data o3; if 1 then do; set a end=e; f = e; end; run;
proc print data=o3 noobs; run;

/* an INNER well-formed if_ inside the block is no longer lost with it
   (QA's F1d: the hole was the outer .do_, not the inner arm). */
data o4; if 1 then do; if 1 then set a; end; run;
proc print data=o4 noobs; run;
