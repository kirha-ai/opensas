//! SAS interpreter — public module root. Re-exports the pieces the CLI and the
//! test runner reach. Each track appends its module here as it lands.
pub const Value = @import("value.zig").Value;
pub const diag = @import("diag.zig");
pub const ast = @import("ast.zig");
pub const pdv = @import("pdv.zig");
pub const dataset = @import("dataset.zig");
pub const lexer = @import("lexer.zig");
pub const parser_expr = @import("parser_expr.zig");
pub const parser = @import("parser.zig");
pub const io = @import("io.zig");
pub const xport = @import("xport.zig");
pub const sas7bdat = @import("sas7bdat.zig");
pub const sas7bcat = @import("sas7bcat.zig");
pub const eval = @import("eval.zig");
pub const functions = @import("functions.zig");
pub const format = @import("format.zig");
pub const exec = @import("exec.zig");
pub const proc = @import("proc.zig");
pub const macro = @import("macro.zig");
pub const sql = @import("sql.zig");

test {
    // Pull every module's `test` blocks into `zig build test`. Append imports
    // here as modules land (ast.zig, diag.zig, …).
    _ = @import("value.zig");
    _ = @import("diag.zig");
    _ = @import("ast.zig");
    _ = @import("pdv.zig");
    _ = @import("dataset.zig");
    _ = @import("lexer.zig");
    _ = @import("parser_expr.zig");
    _ = @import("parser.zig");
    _ = @import("io.zig");
    _ = @import("xport.zig");
    _ = @import("sas7bdat.zig");
    _ = @import("sas7bcat.zig");
    _ = @import("eval.zig");
    _ = @import("functions.zig");
    _ = @import("format.zig");
    _ = @import("exec.zig");
    _ = @import("proc.zig");
    _ = @import("macro.zig");
    _ = @import("sql.zig");
}
