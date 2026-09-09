/* Numbered variable ranges in KEEP=/DROP= dataset options (QA-dsoptrange):
   collectNames used to stop at the `-`, silently keeping only the first name
   and dropping the rest with no diagnostic. Covers input-side (set), output-
   side (data ds(keep=)), and drop=. KEEP/DROP *statements* with ranges are a
   separate (loud) parser gap. */
data have; c1=1; c2=2; c3=3; d=9; run;
data inp; set have(keep=c1-c3); run;
proc print data=inp noobs; run;
data outp(keep=c1-c2); set have; run;
proc print data=outp noobs; run;
data dr; set have(drop=c1-c2); run;
proc print data=dr noobs; run;
