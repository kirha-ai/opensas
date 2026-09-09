/* BUG-collateomittedstart: COLLATE with an OMITTED start-position returned a
   blank instead of running from position 0.

   SAS 9.4 Functions and CALL Routines: Reference, printed p.524, Example 3
   "Returning an ASCII String of a Specific Length" is literally

       data _null_;
          y = collate(,,56);
          put y;
       run;

   and its prose reads "the return code variable y uses a return string length
   of 56, and the COLLATE function returns the first 56 characters of the ASCII
   collating sequence. The remainder of the 200-character string is padded with
   spaces." First 56 characters = positions 0..55, so the empty slot IS position
   0 — documented, working usage, not a give-up and not worth a NOTE.

   opensas returned a one-blank string for it (length 1) while the spelled-out
   collate(0,,56) returned the right 56. The two must agree.

   The contents are control characters, so this fixture pins the LENGTH plus a
   printable window (positions 48.. are the digits, the same run p.522's
   Example 1 shows collate(48,,10) returning) rather than dumping raw bytes.

   An EXPLICIT missing start — collate(.) — is a different thing and still gives
   up as a blank CHARACTER (BUG-charfnsmissingtype); the parser fills an omitted
   slot with an empty string, so the two are distinguishable. */
data _null_;
  length y $256 z $256 a $256 b $256 c $256 dot $256 digits $8 tag $1;

  /* p.524 Example 3, and the spelled-out 0 it must equal */
  y = collate(,,56);
  z = collate(0,,56);
  ly = length(y);
  lz = length(z);
  same = (y = z);
  digits = substr(y, 49, 8);   /* positions 48..55 = '0'..'7', inside the 56 */
  tag = vtype(y);
  put ly= lz= same= digits= 'vtype=' tag;

  /* siblings: the same default-to-0 start with an explicit end-position, and
     with everything after the empty slot omitted (p.522: length "Default 200") */
  a = collate(,65);            /* 0..65 inclusive */
  b = collate(,);
  c = collate(,,);
  la = length(a);
  last_a = rank(substr(a, 66, 1));   /* 65 = 'A' */
  lb = length(b);
  lc = length(c);
  put la= last_a= lb= lc=;

  /* the decline stays: an explicit missing start is a blank, not position 0 */
  dot = collate(., , 56);
  ldot = length(dot);
  tag = vtype(dot);
  put ldot= 'dot vtype=' tag;

  /* every line above is documented usage — nothing may flag */
  put _error_=;
run;
