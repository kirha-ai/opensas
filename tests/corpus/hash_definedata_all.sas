/* BUG-hashdefinedataall (doc-finder tick164): defineData(all:'yes') on a
   dataset:-loaded hash must (a) INCLUDE the key variables among the data —
   SAS: the keys are data too, the documented idiom for keeping the key
   column on .output() — and (b) enumerate the DATASET's schema, not the
   live PDV: this _null_ step carries no id/x columns, so a PDV scan would
   define ZERO data vars and silently output nothing. The output dataset
   must carry id (the key) AND x with correct values. */
data src;
  input id x;
  datalines;
1 10
2 20
3 30
;
run;

data _null_;
  declare hash h(dataset:'src');
  h.defineKey('id');
  h.defineData(all:'yes');
  h.defineDone();
  h.output(dataset:'out');
run;

data _null_; set out; put id= x=; run;
