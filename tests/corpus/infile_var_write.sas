/* BUG-infilevarnoop (qa tick356 F2): assigning `_INFILE_` was a SILENT NO-OP,
   and its mere presence — even on a DEAD branch — blanked every `_INFILE_`
   read in the step (the assignment declared the name in the compile-time PDV,
   so the uninit pass that set refs_infile early-returned and the record
   buffer was never published). `_INFILE_` is now recognised as an automatic
   in ONE place, independent of PDV membership, and a write goes THROUGH to
   the held record so the next INPUT re-parses the edited buffer — the Language Reference: Concepts
   p.517 varying-record-layout look-ahead idiom, pinned side by side with the
   dead-branch shape so the two can never silently disagree again. */
data _null_;
  infile datalines truncover;
  input @;
  if _infile_ =: 'P' then do;
    input @2 product $6. price;
    put "P " product " " price;
  end;
  else if _infile_ =: 'S' then do;
    input @2 store $6. sales;
    put "S " store " " sales;
  end;
  datalines;
Pwidget 199
Sstore1 42
Pgadget 50
;
run;

/* look-ahead WITH an edit: upcase the buffer, the second INPUT re-parses it */
data _null_;
  infile datalines truncover;
  input @;
  _infile_ = upcase(_infile_);
  input a $8.;
  put "edit a=[" a "] buf=[" _infile_ "]";
  datalines;
abcdefgh
;
run;

/* a DEAD-BRANCH assignment must not blank reads that run before it */
data _null_;
  infile datalines truncover;
  input @;
  put "dead buf=[" _infile_ "]";
  if 0 then _infile_ = 'never-runs';
  input a $8.;
  put "dead a=[" a "]";
  datalines;
abcdefgh
;
run;

/* a write after a RELEASING input lands in the stale buffer (SAS: invisible)
   — the next INPUT reads the FRESH record, never the edited text */
data _null_;
  infile datalines truncover;
  input a $3.;
  _infile_ = 'XXX';
  put "rel mid=[" _infile_ "]";
  input b $3.;
  put "rel b=[" b "] buf=[" _infile_ "]";
  datalines;
aa1
bbb
;
run;
