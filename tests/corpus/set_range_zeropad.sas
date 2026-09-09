/* ISS-setrangezeros (GH#27): SET numbered range with ZERO-PADDED endpoints must
   expand to the literal padded member names (ds00 ds01 ds02), not ds0 ds1 ds2.
   Non-padded ranges (GH#21) stay plain. */
data ds00; x=0; run;
data ds01; x=1; run;
data ds02; x=2; run;

/* zero-padded range: ds00-ds02 reads all three padded members (x = 0,1,2) */
data allpad; set ds00-ds02; run;
proc print data=allpad noobs; run;

/* mixed width: pad to widest endpoint (d08..d12 → d08 d09 d10 d11 d12) */
data d08; y=8; run;
data d09; y=9; run;
data d10; y=10; run;
data d11; y=11; run;
data d12; y=12; run;
data allmix; set d08-d12; run;
proc print data=allmix noobs; run;
