/* BUG-selectwhenafterother: a WHEN after OTHERWISE used to fold AHEAD of the
   OTHERWISE into the if-chain, so the post-OTHERWISE WHEN could fire (SAS 9.4
   raises a syntax error — OTHERWISE must be the LAST clause). Step 1 is the
   positive case and prints below; step 2 fails LOUD at parse time (ERROR on
   stderr, exit 1) and prints nothing. If the silent fold regresses, step 2
   would append a='five' here and mismatch.
   expect-rc: 1 */
data _null_;
  do x = 1, 2, 9;
    select (x);
      when (1) put "one";
      when (2) put "two";
      otherwise put "other";
    end;
  end;
run;
data _null_;
  x = 5;
  select (x);
    when (1) a = 'one';
    otherwise a = 'other';
    when (5) a = 'five';
  end;
  put a=;
run;
