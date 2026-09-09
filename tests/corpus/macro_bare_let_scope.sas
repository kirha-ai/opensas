/* BUG-macrobareletscope: a bare %let of a BRAND-NEW name inside a macro is
   LOCAL to that invocation in SAS 9.4 (was leaking to global).
   (a) sibling macros each %let i — no clobber, neither survives to global;
   (b) a bare %let of an EXISTING global still updates the global (no shadow);
   (c) a name an enclosing macro owns updates THERE, not a new inner local. */
%macro a;
  %let i=AAA;
  data _null_; put "A-INSIDE=&i"; run;
%mend;
%macro b;
  %let i=BBB;
  data _null_; put "B-INSIDE=&i"; run;
%mend;
%a
%b
data _null_; put "I-SURVIVES=%symexist(i)"; run;

%let g=1;
%macro m;
  %let g=2;
%mend;
%m
data _null_; put "G-UPDATED=&g"; run;

%macro inner;
  %let z=FROM-INNER;
%mend;
%macro outer;
  %let z=FROM-OUTER;
  %inner
  data _null_; put "Z-NEAREST=&z"; run;
%mend;
%outer
data _null_; put "Z-SURVIVES=%symexist(z)"; run;

/* open-code %let is still global; CALL SYMPUT unaffected */
%let open=STILL-GLOBAL;
data _null_;
  put "OPEN=&open SYMEXIST=%symexist(open) SYMGLOBL=%symglobl(open)";
  call symput('rt', 'RUNTIME');
run;
data _null_; put "RT=&rt"; run;
