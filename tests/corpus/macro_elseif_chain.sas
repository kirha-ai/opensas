/* BUG-macroelseifchain: `%else %if … %then …; %else …;` cascades (the else-if
   idiom, ubiquitous in derivation macros). branchUnit now consumes an
   %if-headed else-branch as a whole nested conditional, so each inner %else
   binds to its own %if — no truncation at the first `;`, no orphaned %else
   running unconditionally, no stray "macro ELSE not resolved" warning. */

/* text-emitting cascade — the taken branch letter is the only text emitted */
%macro grade(s);%if &s >= 90 %then A;%else %if &s >= 80 %then B;%else %if &s >= 70 %then C;%else F;%mend;
data _null_;
  length g $1;
  g = "%grade(95)"; put g=;   /* A */
  g = "%grade(85)"; put g=;   /* B */
  g = "%grade(75)"; put g=;   /* C */
  g = "%grade(50)"; put g=;   /* F */
run;

/* same cascade with %do…%end block branches (generates data-step code) */
%macro gradeb(s);
%if &s >= 90 %then %do; g = "A"; %end;
%else %if &s >= 80 %then %do; g = "B"; %end;
%else %if &s >= 70 %then %do; g = "C"; %end;
%else %do; g = "F"; %end;
%mend;
data _null_;
  length g $1;
  %gradeb(95) put g=;
  %gradeb(85) put g=;
  %gradeb(75) put g=;
  %gradeb(50) put g=;
run;

/* plain single %if/%else must stay correct */
%macro p(n);%if &n > 0 %then POS;%else NEG;%mend;
data _null_;
  length r $3;
  r = "%p(5)";  put r=;
  r = "%p(-2)"; put r=;
run;
