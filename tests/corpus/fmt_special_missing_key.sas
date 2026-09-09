/* NOTE-sas7bcatspecialmiss: a special-missing numeric format KEY (built here
   via CNTLIN START=.A — the .sas7bcat catalog reader decodes the same encoding)
   matches only its OWN missing value: .A → its label; .B and plain . fall to
   OTHER (or the default letter render when no OTHER). Such keys used to be
   silently DROPPED on catalog read / never matched on apply — wrong label text
   for .A–.Z with no diagnostic (D-002 silent data loss). */
data cntl;
  length fmtname $8 type $1 hlo $1 label $10;
  fmtname='missf'; type='N'; hlo='';
  start=1;  label='One';       output;
  start=.A; label='Special A'; output;
  fmtname='missg'; type='N'; hlo='';
  start=.B; label='Bee';       output;
run;
proc format cntlin=cntl;
run;
data _null_;
  a = put(1,  missf.);
  b = put(.A, missf.);
  c = put(.B, missf.);  /* .B has no key in MISSF and no OTHER → default render */
  d = put(.,  missf.);  /* plain . likewise */
  e = put(.B, missg.);
  put 'a=[' a ']';
  put 'b=[' b ']';
  put 'c=[' c ']';
  put 'd=[' d ']';
  put 'e=[' e ']';
run;
