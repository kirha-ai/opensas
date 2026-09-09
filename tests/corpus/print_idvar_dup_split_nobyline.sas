/* GAP-printby-low-tick274 (doc-finder tick274 F4/F5 + LOW batch):
   1. ID∩VAR overlap keeps BOTH columns (SAS ID statement doc);
   2. a duplicated VAR entry also prints twice (VAR is positional);
   3. SPLIT= implies LABEL — no `label` option, header still splits the label;
   4. NOBYLINE sections BY groups without the `g=…` BY line.
   N / DOUBLE / ROUND / WIDTH= remain D-002 fail-loud (unit-tested in main.zig). */
data d;
  input g subj x;
  label x = "Long*Label*Here";
  datalines;
1 101 10
1 102 20
2 103 30
;
run;
proc print data=d noobs; id subj; var subj x; run;
proc print data=d noobs; var x x g; run;
proc print data=d split='*' noobs; var x; run;
proc print data=d noobs nobyline; by g; run;
