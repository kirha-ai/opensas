/* GAP-puttildemodifier — `~` is PUT's documented second modifier (Statements
   ref "PUT Statement: List", printed p.297's slot `variable < : | ~> format.`,
   defined p.298: quotes the value, requires the DSD option in the FILE
   statement). opensas does not implement its DSD quoting (that half lives in
   exec.zig), so the modifier is a NAMED gap — an opensas gap, exit 2, not the
   user's typo. The lexer keeps the source byte on the caret token's text so
   `~` is told from `^` (D-018). Typo twin: rc_put_caret_typo.sas;
   expression-side control: put_tilde_not_control.sas. expect-rc: 2 */
data _null_;
  x = 2353.2;
  put x ~ comma10.2;
run;
