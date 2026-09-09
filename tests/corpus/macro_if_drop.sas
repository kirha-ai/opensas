/* GH#6 ISS-macrodrop: a `drop` statement spliced in by a macro %if branch must
   be honored (regression). a date macro's DAY_ helper leaked into every dataset
   because the conditional drop was parsed but not applied. A true branch drops
   the var; a false branch keeps it (drop text never emitted). GH#6. */
%macro m(clean=1);
data OUT&clean;
  X = 1; DAY_ = 99;
  %if &clean = 1 %then %do;
    drop DAY_;
  %end;
run;
%mend;
%m(clean=1)
%m(clean=0)
data _null_; set OUT1; put "c1 " X= DAY_=; run;
data _null_; set OUT0; put "c0 " X= DAY_=; run;
