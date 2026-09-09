/* PRX /s (dotall) and /m (multiline) modifiers — a session-landed PRX feature
   with no corpus coverage. /s makes `.` span an embedded newline; /m makes
   `^`/`$` anchor at every internal line boundary. Each is contrasted with its
   modifier-less form on the SAME two-line subject so the semantics are pinned,
   not just "matched something". Newline built with BYTE(10). NOTEs off-diff. */
data _null_;
  length subj $8;
  subj = cats('a', byte(10), 'b');   /* "a<LF>b" */

  /* /s: dot crosses the newline; plain dot does not */
  if prxmatch('/a.b/s', subj) then put 's-dotall: MATCH'; else put 's-dotall: NO';
  if prxmatch('/a.b/',  subj) then put 's-plain: MATCH';  else put 's-plain: NO';

  /* /m: ^ anchors at the start of the 2nd line; plain ^ only at string start */
  if prxmatch('/^b/m', subj) then put 'm-anchor: MATCH'; else put 'm-anchor: NO';
  if prxmatch('/^b/',  subj) then put 'm-plain: MATCH';  else put 'm-plain: NO';

  /* $ under /m anchors at end of the 1st line (before the newline) */
  if prxmatch('/a$/m', subj) then put 'm-dollar: MATCH'; else put 'm-dollar: NO';
run;
