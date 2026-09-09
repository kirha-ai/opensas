/* BUG-wherestmtobsorder: the DATA-step WHERE STATEMENT is a read-time filter,
   applied BEFORE firstobs=/obs= count positions WITHIN the WHERE-selected
   subset — identical to the where= OPTION twin (BUG-whereobsorder). opensas
   used to slice the physical firstobs=/obs= range first, THEN filter, so a
   `set a(obs=5); where x>3;` kept x=4,5 instead of x=4,5,6,7,8. */
data a; do x=1 to 10; output; end; run;

/* where STATEMENT + obs= : subset is 4..10, obs=5 caps at 5 rows → 4-8 */
data b; set a(obs=5); where x>3; run;
proc print data=b noobs; run;

/* firstobs= + obs= + where STATEMENT: positions 2..4 of 4..10 → 5,6,7 */
data c; set a(firstobs=2 obs=4); where x>3; run;
proc print data=c noobs; run;

/* obs= alone, NO where: still a physical cap → 1..5 (slice raw, unchanged) */
data d; set a(obs=5); run;
proc print data=d noobs; run;

/* where STATEMENT alone, no firstobs/obs → 9,10 */
data e; set a; where x>8; run;
proc print data=e noobs; run;

/* the where= OPTION twin on the SAME options must agree → 4-8 (not double-applied) */
data f; set a(obs=5 where=(x>3)); run;
proc print data=f noobs; run;

/* keep= + obs= + where STATEMENT together: keep x, filter x>3, positions 1..5 → 4-8 */
data g; set a(keep=x obs=5); where x>3; run;
proc print data=g noobs; run;
