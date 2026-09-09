/* BUG-macrodoscope: the iterative %do index (a) is LOCAL to the macro that
   owns the loop when the name is brand-new (raw setVar leaked it to global),
   and (b) ends at the FIRST value past the bound — start + k*step (SAS 9.4),
   not the last in-range value. */
%macro loop;
  %do i = 1 %to 3;
    data _null_; put "INSIDE=&i"; run;
  %end;
  data _null_; put "AFTER=&i"; run;
%mend;
%loop
data _null_; put "I-SURVIVES=%symexist(i)"; run;

/* reverse: %do j=5 %to 1 %by -1 ends at 0, j stays local too */
%macro rev;
  %do j = 5 %to 1 %by -1;
    data _null_; put "REV=&j"; run;
  %end;
  data _null_; put "REV-AFTER=&j"; run;
%mend;
%rev
data _null_; put "J-SURVIVES=%symexist(j)"; run;

/* a pre-existing GLOBAL name updates in place (nearest existing scope,
   never a shadow) — same rule %let follows (BUG-macrobareletscope) */
%let g=OLD;
%macro upd;
  %do g = 1 %to 2;
  %end;
%mend;
%upd
data _null_; put "G-UPDATED=&g"; run;
