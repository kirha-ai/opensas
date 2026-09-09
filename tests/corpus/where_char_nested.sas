/* NOTE-wherecharnested — premise-audit pin. The ticket claimed: "a bare char
   operand is correctly non-blank-is-true in WHERE, but a char operand NESTED
   inside `and`/`or`/`not` still converts via the shared `truthy()`."
   Verdict: REPRODUCES — and the premise-audit's first job was a
   DISCRIMINATING case, which 'abc'/'0' provide (non-blank-is-true keeps
   them; numeric coercion drops them). Bare `where c;` keeps abc/0/1 (Language Reference: Concepts
   p.216 non-blank rule, BUG-wherebarechar); nested `where c and x=1;` keeps
   only '1' — the two readings provably diverge, so the ticket is NOT
   vacuous. It is also NOT fixed here, deliberately: the oracle is
   ambiguous. DATA Step Statements Ref, WHERE Statement chapter
   (Statements reference, pdf p.373) shows a NESTED numeric
   stand-alone example ('where empnum and ssn;') but for characters says
   "by itself as a WHERE expression" — a qualifier the numeric paragraph
   does not carry. Flipping nested chars to non-blank on that citation alone
   risks trading one non-conformance for another; the ticket was filed
   needs-oracle and one real SAS run settles it.
   Scope when the oracle lands: (a) thread where-context through eval.zig's
   and/or/not arms (callers live in exec.zig/io.zig/sql.zig), or (b) parser
   desugar wrapping bare char operands of and/or/not in WHERE clauses with a
   __wherebool builtin (parser.zig + functions.zig only). Pinned below:
   CURRENT behaviour, so the fix's golden diff is exactly the semantic flip. */
data t;
  length c $4;
  c='abc'; x=1; output;
  c='0';   x=1; output;
  c='1';   x=1; output;
  c='';    x=1; output;
run;
title 'bare: where c';            proc print data=t; where c; run;
title 'nested: where c and x=1';  proc print data=t; where c and x=1; run;
title 'nested: where not c';      proc print data=t; where not c; run;
title 'nested: where c or x=2';   proc print data=t; where c or x=2; run;
