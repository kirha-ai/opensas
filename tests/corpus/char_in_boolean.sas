/* BUG-charinboolean: a CHARACTER value in a truth context is auto-converted
   char→numeric first (w. informat; blank/unparseable → missing), then numeric
   truthiness — '0' and 'abc' are BOTH false, '2.5' true. */
data _null_;
  length c $3;
  /* literals */
  if '0'   then put 'lit0 T';   else put 'lit0 F';
  if '1'   then put 'lit1 T';   else put 'lit1 F';
  if 'abc' then put 'litabc T'; else put 'litabc F';
  if '2.5' then put 'lit25 T';  else put 'lit25 F';
  if ' '   then put 'litblk T'; else put 'litblk F';
  /* char variables (padded to declared length) behave the same */
  c = '0';   if c then put 'var0 T';   else put 'var0 F';
  c = '2.5'; if c then put 'var25 T';  else put 'var25 F';
  c = 'abc'; if c then put 'varabc T'; else put 'varabc F';
  /* AND / OR / NOT operands route through the same truthiness */
  if '0' or 1    then put 'or T';  else put 'or F';
  if '1' and '0' then put 'and T'; else put 'and F';
  if not 'abc'   then put 'not T'; else put 'not F';
  /* DO WHILE on a char condition: '0' → 0 → body never runs */
  n = 0;
  do while ('0');
    n + 1;
  end;
  put 'while0 n=' n;
  /* DO UNTIL on a char flag: '0' is false (loop), '1' true (exit) */
  m = 0;
  flag = '0';
  do until (flag);
    m + 1;
    if m >= 2 then flag = '1';
  end;
  put 'until m=' m;
  /* numeric control: unchanged path, byte-identical */
  x = 5;
  if x > 1 then put 'num T'; else put 'num F';
run;
