/* BUG-calllabel2arg: DATA-step CALL LABEL(var, out) writes the variable's
   declared label; an unlabeled variable yields its NAME (SAS 9.4 F&C Ref
   p.322). Used to write nothing (silent blank, no diagnostic).
   GAP-calloutarg-note: the pure-output args (lb/lb2/pos/len) emit no
   "Variable X is uninitialized." NOTE (log fidelity; checked in-file). */
data _null_;
  label wt='Body Weight';
  wt=70; ht=180;
  length lb $40;
  call label(wt, lb);
  call label(ht, lb2);
  s="a,b,c";
  call scan(s, 2, pos, len, ',');
  w=substr(s,pos,len);
  put lb= lb2= pos= len= w=;
run;
