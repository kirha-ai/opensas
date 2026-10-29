/* BUG-updateinflag: `in=` on UPDATE sources was silently never set (stayed .,
   `if a and b then` logic never fired — the Statements ref UPDATE Example 2
   `update health(rename=(weight=ORIG) in=a) fitness(drop=name team in=b); by id;`
   relies on it). SAS tracks IN= like MERGE: 1 when that source contributed to
   the obs being written — master 1 on every master group (0 on a new
   transaction-only key), transaction 1 once any trans obs applied (duplicate
   trans keys still yield ONE obs). Flags are temporary: dropped from output. */
data m; input k x; datalines;
1 10
2 20
;
data t; input k x; datalines;
1 11
1 12
3 30
;
data out; update m(in=im) t(in=it); by k;
  fm=im; ft=it;
run;
proc print data=out noobs; run;

/* Example-2 shape: rename= keeps the original, in= gates the change logic. */
data health; input id name $ team $ weight; datalines;
1114 ann  red  125
1441 bill blue 145
;
data fitness; input id weight; datalines;
1114 119
;
data h2; update health(rename=(weight=orig) in=a) fitness(in=b); by id;
  if a and b then change=abs(orig-weight);
run;
proc print data=h2 noobs; run;
