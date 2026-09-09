/* BUG-charfnsnodomerr: the CHARACTER give-up arms are type-correct (that was
   BUG-charfnsmissingtype, pinned next door in charfns_missing_type) but they
   were also DIAGNOSTICALLY SILENT — blank returned, no NOTE, _ERROR_ left 0 —
   while their numeric siblings (sqrt(-1) & co.) were loud. Under fail-loud a
   silent give-up is the weaker behaviour, so the arms the SAS 9.4 Functions and
   CALL Routines: Reference says are DIAGNOSED now route through domErrChar:
   NOTE + _ERROR_=1 + blank, one event.

   Per-arm citation, because "consistency" alone is not a reason to make
   something loud:
     BYTE p.282       `n` carries `Range 0-255`, so an out-of-range or missing n
                      is p.5's case verbatim: "If the value of an argument is
                      invalid (for example, missing or outside the prescribed
                      range), SAS writes a note to the log indicating that the
                      argument is invalid, sets _ERROR_ to 1, and sets the
                      result to a missing value."
     COLLATE p.522    "256 positions, referenced with the position numbers 0
                      through 255", "end-position must be larger than
                      start-position", "The maximum end-position ... is 255"
                      -> three prescribed ranges, p.5 applies to each.
     HASHING p.976    "If method is invalid, the returned digest is blank, and a
     HMAC    p.979    note, warning, or error message is issued stating that the
                      argument is invalid." Doc-mandated word for word.

   And the two arms DECLINED, which is the point of the fixture as much as the
   loud ones:
     COLLATE omitted/missing start-position -- p.524 Example 3 is literally
       `y = collate(,,56);`, a WORKING call, and an omitted argument arrives
       here as a missing number. A NOTE would fire on documented-correct usage.
     COLLATE `length` -- p.522 gives it no range at all ("Default 200"), so
       there is no prescribed range for p.5 to be outside of.

   The NOTEs go to stderr, which the corpus does not diff; _ERROR_ is the
   stdout-visible half of the same event, so that is what this pins. The run
   still exits 0 -- a NOTE is not a user error (D-009) and never was: sqrt(-1)
   has behaved exactly this way all along, and the last line proves it. */
data _null_;
  /* ---- LOUD: NOTE + _ERROR_=1, blank result, per the citations above ---- */
  b1 = byte(-1);          put 'byte(-1)        _error_=' _error_ ' [' b1 ']'; _error_ = 0;
  b2 = byte(999);         put 'byte(999)       _error_=' _error_ ' [' b2 ']'; _error_ = 0;
  b3 = byte(.);           put 'byte(.)         _error_=' _error_ ' [' b3 ']'; _error_ = 0;
  c1 = collate(-1);       put 'collate(-1)     _error_=' _error_ ' [' c1 ']'; _error_ = 0;
  c2 = collate(300);      put 'collate(300)    _error_=' _error_ ' [' c2 ']'; _error_ = 0;
  c3 = collate(65,60);    put 'collate(65,60)  _error_=' _error_ ' [' c3 ']'; _error_ = 0;
  c4 = collate(65,999);   put 'collate(65,999) _error_=' _error_ ' [' c4 ']'; _error_ = 0;
  h1 = hashing('nope','x');            put 'hashing bad     _error_=' _error_ ' [' h1 ']'; _error_ = 0;
  h2 = hashing_hmac('nope','k','m');   put 'hmac bad        _error_=' _error_ ' [' h2 ']'; _error_ = 0;

  /* ---- DOC-SILENT: still blank, still quiet, _ERROR_ untouched ---- */
  q1 = collate(.);        put 'collate(.)      _error_=' _error_ ' [' q1 ']'; _error_ = 0;
  q2 = collate(,,56);     put 'collate(,,56)   _error_=' _error_;             _error_ = 0;
  q3 = collate(65,,0);    put 'collate(65,,0)  _error_=' _error_ ' [' q3 ']'; _error_ = 0;

  /* ---- the good paths gained nothing: same values, still quiet ---- */
  g1 = byte(80);          put 'byte(80)=' g1 '        _error_=' _error_;
  g2 = collate(65,67);    put 'collate(65,67)=' g2 '  _error_=' _error_;
  g3 = collate(65,65);    put 'collate(65,65)=' g3 '    _error_=' _error_;  /* end = start, unchanged */
  g4 = collate(48,,10);   put 'collate(48,,10)=' g4 ' _error_=' _error_;    /* p.522 Example 1 */
  g5 = hashing('md5','abc'); put 'hashing md5=' g5;
  _error_ = 0;

  /* the numeric sibling this was aligned to -- unchanged, and still rc 0 */
  n1 = sqrt(-1);          put 'sqrt(-1)        _error_=' _error_ ' ' n1;
  _error_ = 0;
run;
