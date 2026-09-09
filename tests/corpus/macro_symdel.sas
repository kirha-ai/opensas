/* GAP-macrosymdel: %SYMDEL deletes macro variables (warn if absent unless
   NOWARN); the argument text must not corrupt the parse. Synthetic.
   GAP-macrosymdel. */
%let g=KEEP;
data _null_; put "BEFORE=[&g]"; run;
%symdel g;
data _null_; put "AFTER-EXISTS=[%symexist(g)]"; run;
%let h=1; %let i=2;
%symdel h i / nowarn;
data _null_; put "AFTER2=[%symexist(h)%symexist(i)]"; run;
