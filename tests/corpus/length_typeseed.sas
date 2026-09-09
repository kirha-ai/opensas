/* LENGTH-typeseed — premise-audit pin. The ticket worried: "if a program
   declares a `*DTC` var ONLY via a numeric metadata length (no `$`) with no
   char assignment before a numeric-context use, the compile-time guess is the
   sole safety net".
   Verdict: NOT OUR BUG — the declared length's `$` (or its absence) governs
   the type exactly as SAS: a NUMERIC metadata length yields a numeric var,
   and assigning a date string into it raises the SAME loud surface SAS
   raises (char->num conversion NOTE + 'Invalid numeric data' NOTE, value
   missing) — never silent wrong output. A `$`-length template types Char
   (control below). So if a study's `*DTC` comes out numeric, the numeric
   length came from the STUDY's own metadata (ticket's own dev2 note), and
   opensas is conformant for that declaration. The actual shell-generator macro
   audit needs the gitignored study data, absent from this tree; the full
   synthetic matrix is pinned here. (2a4180d5's over-long-length refusal is
   orthogonal: it caps >32767, it does not touch typing.) */
data a;
  length x 8;           /* numeric metadata length, no $ — the ticket's shape */
  x = "2024-01-01";     /* -> Num, conversion + invalid-data NOTEs, x=. (SAS) */
  put x=;
run;
proc contents data=a; run;
data b;
  length y $8;          /* control: $-length template -> Char                  */
  y = "2024-01-01";
  put y=;
run;
proc contents data=b; run;
data c;
  length z 8;           /* numeric length, numeric use — the safety net holds  */
  z = 5;
  put z=;
run;
