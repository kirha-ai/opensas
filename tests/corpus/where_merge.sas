/* BUG-wheremerge (QA-audit42): a WHERE statement filters EVERY merge input
   pre-read, as in SAS — it was silently ignored for MERGE (unfiltered rows). */
data l; do id = 1 to 4; x = id * 10; output; end; run;
data r; do id = 1 to 4; y = id * 100; output; end; run;

data m; merge l r; by id; where id > 1; run;
proc print data=m; run;
