/* BUG-whereobsorder: dataset-option ordering fixes.
   1) WHERE= applies BEFORE firstobs=/obs= count positions within the
      WHERE-selected subset (opensas sliced the physical range first, so
      set a(obs=5 where=(x>3)) kept 4,5 instead of 4,5,6,7,8).
   2) keep= AND drop= together: a var survives iff it is in keep= (when
      given) AND not in drop= (keep= used to silently disable drop=). */
data a; do x=1 to 10; output; end; run;

/* where= + obs= on SET: subset is 4..10, obs=5 caps at 5 rows → 4-8 */
data b; set a(obs=5 where=(x>3)); run;
proc print data=b noobs; run;

/* same options on PROC input */
proc print data=a(obs=5 where=(x>3)) noobs; run;

/* firstobs= + obs= + where= together: positions 2..4 of 4..10 → 5,6,7 */
data c; set a(firstobs=2 obs=4 where=(x>3)); run;
proc print data=c noobs; run;

/* obs= alone: still a physical cap → 1..5 */
data d; set a(obs=5); run;
proc print data=d noobs; run;

/* where= alone: unchanged → 9,10 */
data e; set a(where=(x>8)); run;
proc print data=e noobs; run;

/* keep= + drop= together: q is kept then dropped → only x survives */
data g; x=1; q=2; z=3; run;
data f; set g(keep=x q drop=q); run;
proc print data=f noobs; run;
