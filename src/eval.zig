//! Expression evaluator — `(ast.Expr, *Pdv) → Value`. Walks the immutable AST
//! (M0.2), reads variables from the PDV (M0.3), and returns a SAS `Value` (M0.1).
//! Matches the lexer's house style: small error set, arena allocation, names
//! compared case-insensitively (via the PDV).
//!
//! The SAS semantics that actually bite here:
//!   * Missing *propagates* through arithmetic (`. + 1` → `.`) but does NOT in
//!     comparisons — there, missing is simply the lowest value (`. < 5` is true).
//!   * Every comparison / logical op yields a numeric `1` or `0`, never a bool.
//!   * A char used in arithmetic/comparison auto-converts to numeric; a numeric
//!     used in `||` auto-converts to char.
//!   * Runtime mishaps (divide-by-zero, bad numeric text) are NOTEs + a missing
//!     result — SAS keeps going. The exceptions: an out-of-range array subscript
//!     is a SAS execution ERROR that aborts the DATA step via `error.ExecError`
//!     (BUG-arrayoorerror); `OutOfMemory` comes from the arena.
//!
//! Functions (`sum(...)`, `substr(...)`) are Track B2, a separate file that
//! depends on this one. To avoid a circular import, calls dispatch through an
//! optional `call_fn` hook that B2 installs; unset, a call is an unsupported
//! diagnostic returning missing. ponytail: one nullable hook for a known
//! consumer, not a plugin registry.

const std = @import("std");
const ast = @import("ast.zig");
const diag = @import("diag.zig");
const pdv_mod = @import("pdv.zig");
const Value = @import("value.zig").Value;

// diag.Error (OutOfMemory + Lex/Parse/ExecError) so an out-of-range array
// subscript can abort the DATA step LOUD (BUG-arrayoorerror), mirroring
// exec.zig's Error. A superset of the old Allocator.Error, so every existing
// `try` still type-checks.
pub const Error = diag.Error;

/// B2 installs one of these to resolve function calls. Args are already
/// evaluated (SAS built-ins are all eager). The hook may allocate in
/// `ev.arena` and report through `ev.diags`.
pub const CallFn = *const fn (ev: *Evaluator, name: []const u8, args: []const Value) Error!Value;

/// PERF-inlist: a literal `x in (v1,…,vK)` is desugared (parser_expr `parseInList`)
/// into a left-leaning `x=v1 or x=v2 or …` chain, so eval re-walked a K-deep tree
/// per row → O(rows·K). When the chain is a variable tested against an all-numeric,
/// all-finite literal list of ≥ IN_SET_MIN elements, we recognize it ONCE, build a
/// membership set, and probe O(1)/row instead. NOT IN (`and` of `ne`) is the same
/// set, negated. Any non-literal / non-`.num` / special-missing operand, a mixed
/// range, a non-variable lhs, or a short list → left unrecognized (the correct
/// OR-chain runs unchanged). See `buildInSet`.
const IN_SET_MIN = 8;
const InSet = struct {
    negated: bool, // true: NOT IN (and-of-ne); false: IN (or-of-eq)
    var_name: []const u8, // the shared lhs variable
    set: std.AutoHashMapUnmanaged(u64, void), // canonical f64 bits of each literal
};

pub const Evaluator = struct {
    arena: std.mem.Allocator,
    pdv: *pdv_mod.Pdv,
    diags: *diag.Diagnostics,
    call_fn: ?CallFn = null,
    /// LAG/DIF state (semantics live in functions.zig). Keyed per call site;
    /// each value is that call's FIFO of recent inputs. Holds `Value` (not just
    /// f64) so `lag()` of a CHARACTER variable returns the prior row's string
    /// (BUG-lagchar); DIF still coerces to numeric. Fresh per Evaluator — i.e.
    /// per DATA step — so it resets between steps but survives the iteration loop.
    lag: std.StringHashMapUnmanaged(std.ArrayList(Value)) = .empty,
    /// Allocator for cross-iteration state (the `lag` map and its FIFOs/RNG
    /// streams): the DATA-step executor swaps `arena` to a per-row scratch
    /// (BUG-datastepoom), so state that must survive a row lives here instead.
    /// Null → `arena` (single-arena users unchanged).
    state_arena: ?std.mem.Allocator = null,
    /// PERF-inlist: recognized IN/NOT-IN chains, keyed by the chain's root node
    /// (`*const ast.Expr`, stable across rows). `null` = examined, not optimizable
    /// (cached so we don't re-walk it each row). Lives in `state_arena` like `lag`.
    in_sets: std.AutoHashMapUnmanaged(*const ast.Expr, ?InSet) = .empty,
    /// BUG-declaredobjnamevalue: the names this DATA step declared as COMPONENT
    /// OBJECTS (`declare hash h;` / `declare hiter hi;` / `h = _new_ hash();`).
    /// Component Objects Ref printed p.12: "The DECLARE statement tells the
    /// compiler that the object reference myhash is of type hash" — the name is
    /// an object reference, not a numeric or character variable, so it has no
    /// value for `evalVariable` to hand back. The executor owns the list (one
    /// per step, filled by its compile walk) and we hold a POINTER, so a later
    /// declare is visible without re-wiring. Null in every other Evaluator
    /// (SQL / PROC / macro / informat): those namespaces have no objects.
    objects: ?*const std.ArrayList([]const u8) = null,

    pub fn stateArena(self: *const Evaluator) std.mem.Allocator {
        return self.state_arena orelse self.arena;
    }

    pub fn eval(self: *Evaluator, e: *const ast.Expr) Error!Value {
        return switch (e.*) {
            .num => |x| .{ .num = x },
            .str => |s| .{ .str = s },
            .missing => Value.missing,
            .variable => |name| self.evalVariable(name),
            .unary => |u| self.evalUnary(u),
            // PERF-inlist: an OR/AND chain may be an all-literal IN/NOT-IN — probe
            // the membership-set fast path (falls through to evalBinary if not).
            .binary => |b| if (b.op == .@"or" or b.op == .@"and") self.evalOrAnd(e, b) else self.evalBinary(b),
            .call => |c| self.evalCall(c),
            .array_ref => |ar| self.evalArrayRef(ar),
        };
    }

    /// THE one point where a bare name becomes a value — every EXPRESSION
    /// position routes here: an assignment RHS, an IF/SELECT condition, a DO
    /// bound, an array subscript, a function argument, a hash method's
    /// `key:`/`data:` slot, WHERE. (A PUT item is not an `ast.Expr` and is the
    /// one exception — see `rejectObjectName` below.)
    ///
    /// BUG-declaredobjnamevalue: a DATA-step component-object reference shares
    /// the variable namespace but is NOT a value, so `x = h + 1;` and
    /// `h.add(key: 1, data: inner);` used to fabricate a numeric missing and
    /// exit 0 — the silent-wrong-answer class D-002 exists to prevent. The
    /// SAS 9.4 volumes give no verbatim log text for this, so the BASIS is the
    /// house fail-loud rule plus the type fact cited at `objects` above. rc 1,
    /// not 2: writing an object name where a value belongs is invalid SAS, a
    /// user error (D-009b(ii)), so it must NOT be routed through `failGap`.
    /// ponytail: checked at the READ, so a never-executed `if 0 then x = h;`
    /// stays quiet where SAS 9.4 rejects it at compile time — no value is
    /// fabricated either way; add a compile-pass scan if a program needs the
    /// earlier report.
    fn evalVariable(self: *Evaluator, name: []const u8) Error!Value {
        try self.rejectObjectName(name);
        // Unknown variable → numeric missing. Auto-declaring it (with the
        // SAS "uninitialized" NOTE) is the executor's job, not the evaluator's.
        return self.pdv.get(name) orelse Value.missing;
    }

    /// The BUG-declaredobjnamevalue predicate, kept `pub` for its ONE other
    /// entry class: a PUT item is not an `ast.Expr`, so exec.zig's PUT renderer
    /// reads the PDV itself and never reaches `evalVariable` — `put h;` printed
    /// a fabricated `.` at exit 0 for the same reason `x = h + 1;` did. Two
    /// entry classes, one predicate, one message (the shape
    /// BUG-hashofhashexplicit settled), so the two cannot drift apart.
    pub fn rejectObjectName(self: *Evaluator, name: []const u8) Error!void {
        if (self.objects) |objs| for (objs.items) |o| {
            if (std.ascii.eqlIgnoreCase(o, name))
                return self.diags.fail(error.ExecError, 0, "Object {s} cannot be used as a value: {s} is a DATA step component object reference (declare hash/hiter), not a numeric or character variable.", .{ name, name });
        };
    }

    /// `a{i}`: evaluate the subscript, then read the i-th (1-based) member
    /// variable from the PDV. A missing subscript → missing; an out-of-range one
    /// is a SAS ERROR that halts the step (BUG-arrayoorerror, see subscriptOor).
    /// A special-list array (`array v{*} _numeric_;`) resolves its members from the
    /// live PDV here (GH#48). The parser folds `{lo:hi}` subscripts to 1-based
    /// offsets at parse time (ARRAY-lobound), so the span checked is always 1..N.
    fn evalArrayRef(self: *Evaluator, ar: ast.ArrayRef) Error!Value {
        const elements = if (ar.special) |k| try specialArrayNames(self.arena, self.pdv, k) else ar.elements;
        const x = try self.toNum(try self.eval(ar.index));
        // Compare against bounds as a float first: a huge/negative subscript may
        // not fit i64, so guard before @intFromFloat (which panics on overflow).
        // A MISSING (NaN) subscript is out of range too (BUG-arraysubmissing): NaN
        // fails every `<`/`>` compare, so it must be caught explicitly or it slips
        // past the span check — SAS 9.4 halts the step, same as any OOR.
        const xf = @floor(x);
        if (std.math.isNan(x) or xf < 1 or xf > @as(f64, @floatFromInt(elements.len)))
            return self.subscriptOor(xf, ar.name, ar.line);
        const i: i64 = @intFromFloat(xf);
        return self.pdv.get(elements[@intCast(i - 1)]) orelse Value.missing;
    }

    /// BUG-arrayoorerror: SAS 9.4 treats an out-of-range array subscript as an
    /// execution-time ERROR ("Array subscript out of range") that sets _ERROR_=1
    /// and stops the DATA step at the offending statement — a soft set-to-missing
    /// would let a bad index sail through a clinical program. Fail loud: report
    /// the ERROR, flag _ERROR_, and abort the step via ExecError. `line` is the
    /// source line of the subscript reference (NOTE-arrayoorlineno; 0 = unknown,
    /// e.g. a synthetic index); tokens carry no column, so column stays 0.
    fn subscriptOor(self: *Evaluator, xf: f64, name: []const u8, line: usize) Error {
        const e = self.diags.fail(error.ExecError, line, "Array subscript {d} out of range for {s} at line {d} column 0.", .{ xf, name, line });
        self.setError() catch {}; // _ERROR_=1; losing it to OOM doesn't soften the abort
        return e;
    }

    fn evalUnary(self: *Evaluator, u: ast.Unary) Error!Value {
        const v = try self.eval(u.operand);
        return switch (u.op) {
            .neg => blk: {
                const x = try self.toNum(v);
                break :blk if (std.math.isNan(x)) Value.missing else .{ .num = -x };
            },
            .not => boolVal(!v.truthy()), // NOT of missing/blank is 1 (they are false)
        };
    }

    fn evalBinary(self: *Evaluator, b: ast.Binary) Error!Value {
        // SAS does not short-circuit; both sides always evaluate.
        const l = try self.eval(b.lhs);
        const r = try self.eval(b.rhs);
        return switch (b.op) {
            .add, .sub, .mul, .div, .pow => self.arith(b.op, l, r),
            // MIN (`><`) / MAX (`<>`) operators: return the smaller/larger operand
            // by SAS ordering (missing ranks lowest, via cmp). A tie keeps l.
            .min => if (try self.cmp(l, r) == .gt) r else l,
            .max => if (try self.cmp(l, r) == .lt) r else l,
            .eq => boolVal(try self.cmp(l, r) == .eq),
            .ne => boolVal(try self.cmp(l, r) != .eq),
            .lt => boolVal(try self.cmp(l, r) == .lt),
            .le => boolVal(try self.cmp(l, r) != .gt),
            .gt => boolVal(try self.cmp(l, r) == .gt),
            .ge => boolVal(try self.cmp(l, r) != .lt),
            .@"and" => boolVal(l.truthy() and r.truthy()),
            .@"or" => boolVal(l.truthy() or r.truthy()),
            .concat => .{ .str = try std.mem.concat(self.arena, u8, &.{ try self.concatStr(b.lhs, l), try self.concatStr(b.rhs, r) }) },
        };
    }

    /// PERF-inlist fast path for an OR/AND node. On first sight the node is
    /// examined once (`buildInSet`) and the verdict cached by node pointer; a
    /// recognized IN/NOT-IN then probes the set O(1)/row. Anything else falls
    /// through to the ordinary `evalBinary` (byte-identical to before).
    fn evalOrAnd(self: *Evaluator, e: *const ast.Expr, b: ast.Binary) Error!Value {
        const gop = try self.in_sets.getOrPut(self.stateArena(), e);
        if (!gop.found_existing) gop.value_ptr.* = try self.buildInSet(e, b);
        const is = gop.value_ptr.* orelse return self.evalBinary(b);
        // The chain compares `var` numerically to every (numeric) literal, so the
        // per-row test is numeric regardless of var type — matching the OR-chain's
        // `cmp`, which coerces a char operand via toNum. ponytail: a char var emits
        // ONE conversion NOTE here vs one-per-element in the OR-chain (the value is
        // identical, and once-per-comparison is the more SAS-faithful log anyway).
        const x = try self.toNum(self.pdv.get(is.var_name) orelse Value.missing);
        var member = false;
        if (!std.math.isNan(x)) { // finite-only set: a missing var never matches
            var k = x;
            if (k == 0) k = 0; // -0.0 → +0.0 (they compare equal under cmpNum)
            member = is.set.contains(@as(u64, @bitCast(k)));
        }
        return boolVal(if (is.negated) !member else member);
    }

    /// Recognize a left-leaning `x=v1 or … or x=vK` (IN) or `x<>v1 and … and x<>vK`
    /// (NOT IN) where `x` is one variable and every `vi` is a FINITE numeric literal
    /// (K ≥ IN_SET_MIN). Returns the membership set, or null to keep the OR-chain
    /// (any non-literal operand, a range, a non-variable lhs, a special-missing/NaN
    /// literal, or a short list). Runs once per node; the set lives in state_arena.
    fn buildInSet(self: *Evaluator, e: *const ast.Expr, b: ast.Binary) Error!?InSet {
        const negated = b.op == .@"and";
        const want: ast.BinOp = if (negated) .ne else .eq;
        var var_name: ?[]const u8 = null;
        var vals: std.ArrayList(f64) = .empty; // temp; the set is what we keep
        var node: *const ast.Expr = e;
        // walk the left spine: each rhs is one comparison element
        while (node.* == .binary and node.binary.op == b.op) {
            if (!try collectInElem(node.binary.rhs, want, &var_name, &vals, self.arena)) return null;
            node = node.binary.lhs;
        }
        if (!try collectInElem(node, want, &var_name, &vals, self.arena)) return null; // leftmost element
        if (vals.items.len < IN_SET_MIN) return null;
        var set: std.AutoHashMapUnmanaged(u64, void) = .empty;
        const sa = self.stateArena();
        for (vals.items) |v| {
            var k = v;
            if (k == 0) k = 0; // canonicalize -0.0
            try set.put(sa, @as(u64, @bitCast(k)), {});
        }
        return InSet{ .negated = negated, .var_name = var_name.?, .set = set };
    }

    /// The name-taking `…x` twin of a V-metadata function, or null if `name`
    /// isn't in the family. Mirrors parser.zig `vMetaX`, plus VTYPE/VLENGTH
    /// (whose bare-variable forms are handled elsewhere but whose array-element
    /// form routes here). Kept local: eval.zig must not import the parser.
    fn vMetaTwin(name: []const u8) ?[]const u8 {
        const eqi = std.ascii.eqlIgnoreCase;
        if (eqi(name, "vname")) return "vnamex";
        if (eqi(name, "vtype")) return "vtypex";
        if (eqi(name, "vlabel")) return "vlabelx";
        if (eqi(name, "vlength")) return "vlengthx";
        if (eqi(name, "vvalue")) return "vvaluex";
        if (eqi(name, "vformat")) return "vformatx";
        if (eqi(name, "vformatn")) return "vformatnx";
        if (eqi(name, "vformatw")) return "vformatwx";
        if (eqi(name, "vformatd")) return "vformatdx";
        if (eqi(name, "vinformat")) return "vinformatx";
        if (eqi(name, "vinformatn")) return "vinformatnx";
        if (eqi(name, "vinformatw")) return "vinformatwx";
        if (eqi(name, "vinformatd")) return "vinformatdx";
        return null;
    }

    fn evalCall(self: *Evaluator, c: ast.Call) Error!Value {
        // __dimchk — synthetic node the parser emits for a MULTI-dimensional array
        // reference (parser_expr.arraySubscript). SAS 9.4 checks EACH subscript
        // against ITS dimension's bounds BEFORE folding to a flat index; without
        // this, a per-dimension OOR (`a{3,1}` / `a{1,3}` on a{2,2}) silently carries
        // into a valid-but-WRONG flat slot — reads/writes the wrong element with no
        // error (BUG-arraymultidimoor, data corruption). Args: [0]=name, [1]=line,
        // then per dimension a triple (idx_expr, lo, size). Each subscript is
        // truncated (@floor) to an integer like the 1-D path, then bounds-checked;
        // an out-of-range one fails loud via the SAME path as the flat-index guard
        // (subscriptOor / BUG-arrayoorerror). Returns the 1-based row-major flat index.
        if (std.ascii.eqlIgnoreCase(c.name, "__dimchk")) {
            const name = c.args[0].str;
            const line: usize = @intFromFloat(c.args[1].num);
            const ndims = (c.args.len - 2) / 3;
            var flat: f64 = 1; // 1-based: elements[flat-1]
            var m: usize = 0;
            while (m < ndims) : (m += 1) {
                const base = 2 + m * 3;
                const idx = @floor(try self.toNum(try self.eval(&c.args[base])));
                const lo = c.args[base + 1].num;
                const size = c.args[base + 2].num;
                if (std.math.isNan(idx) or idx < lo or idx > lo + size - 1)
                    return self.subscriptOor(idx, name, line);
                var mult: f64 = 1; // Π sizes of the dimensions after m (SAS row-major)
                var k = m + 1;
                while (k < ndims) : (k += 1) mult *= c.args[2 + k * 3 + 2].num;
                flat += (idx - lo) * mult;
            }
            return .{ .num = flat };
        }
        // dim/hbound/lbound of a SPECIAL-LIST array (`array v{*} _numeric_;`): the
        // parser can't count members at parse time, so it left the array-name arg as
        // an `array_ref` carrying its `special` kind. Count the matching PDV vars now
        // (GH#48). A named array was const-folded to a number and never reaches here.
        if (c.args.len >= 1 and c.args[0] == .array_ref) if (c.args[0].array_ref.special) |k| {
            const eqi = std.ascii.eqlIgnoreCase;
            if (eqi(c.name, "dim") or eqi(c.name, "hbound") or eqi(c.name, "lbound")) {
                const names = try specialArrayNames(self.arena, self.pdv, k);
                if (names.len == 0)
                    self.diags.report(.err, 0, "ARRAY {s}: special list matched no variables", .{c.args[0].array_ref.name}) catch {};
                return if (eqi(c.name, "lbound")) .{ .num = 1 } else .{ .num = @floatFromInt(names.len) };
            }
        };
        // V-meta family on an ARRAY ELEMENT: vname(ch[i]), vtype(ch[i]), … .
        // parser.rewriteVMeta only rewrites the bare `vfunc(NAME)` form; a
        // dynamic subscript (`[i]`) never matches, so resolve the element's
        // backing variable name here — `ar.elements` is the parse-time member
        // list — and dispatch to the name-taking `…x` twin (mirrors BUG-vlength).
        if (c.args.len == 1 and c.args[0] == .array_ref) {
            if (vMetaTwin(c.name)) |twin| {
                const ar = c.args[0].array_ref;
                const x = try self.toNum(try self.eval(ar.index));
                const xf = @floor(x);
                if (std.math.isNan(x)) return Value.missing;
                if (xf < 1 or xf > @as(f64, @floatFromInt(ar.elements.len)))
                    return self.subscriptOor(xf, ar.name, ar.line);
                const idx: usize = @intFromFloat(xf);
                if (self.call_fn) |f| {
                    var a1: [1]Value = .{.{ .str = ar.elements[idx - 1] }};
                    return f(self, twin, &a1);
                }
            }
        }
        // VLENGTH(var): the storage (declared) length, distinct from the value width
        // — only resolvable from the variable itself, not its (evaluated) value, so
        // handle a bare-variable argument here where the PDV is in reach
        // (BUG-vlength). A non-variable arg falls through to VLENGTH-of-a-value.
        if (std.ascii.eqlIgnoreCase(c.name, "vlength") and c.args.len == 1 and c.args[0] == .variable) {
            if (self.pdv.indexOf(c.args[0].variable)) |i| {
                const v = self.pdv.vars.items[i];
                // a declared numeric LENGTH<8 (3..7) is the storage length; else 8 (GH#59)
                if (v.type == .num) return .{ .num = if (v.numlen >= 3 and v.numlen < 8) @floatFromInt(v.numlen) else 8 };
                if (v.len > 0) return .{ .num = @floatFromInt(v.len) };
            }
        }
        // LENGTHC(var): the DECLARED char width incl. trailing blanks (GAP-lengthc-declared).
        // opensas stores char values UNPADDED (EPIC-charfixedwidth deferred), so read the
        // declared width from the variable directly — same bare-var precedent as VLENGTH.
        // A non-var arg, or a var with no declared LENGTH (len==0), falls through to the
        // value-based lengthc (counts the value's bytes). LENGTH/LENGTHN (used/trimmed) unaffected.
        if (std.ascii.eqlIgnoreCase(c.name, "lengthc") and c.args.len == 1 and c.args[0] == .variable) {
            if (self.pdv.indexOf(c.args[0].variable)) |i| {
                const v = self.pdv.vars.items[i];
                if (v.type == .char and v.len > 0) return .{ .num = @floatFromInt(v.len) };
            }
        }
        // `of x:` evaluated AS the call (a CALL statement's args are evaluated
        // one by one, never through the loop below): valid SAS there too
        // (funcref printed p.6) but only the function-arg path expands it —
        // loud GAP (rc 2), never a fabricated missing.
        if (std.ascii.eqlIgnoreCase(c.name, "__ofprefix")) {
            diag.markGap();
            return self.diags.fail(error.ExecError, 0, "the name: prefix form of var_list is only supported in function arguments", .{});
        }
        // `of _numeric_ / _all_ / _character_` — the parser leaves the special
        // list name; expand it here to the current PDV's matching variables (the
        // runtime list can't be known at parse time). Skip automatic/helper vars.
        var argv: std.ArrayList(Value) = .empty;
        for (c.args) |*arg| {
            // `of x:` (Language Reference: Concepts printed p.70 Table 4.5) — arrives as a synthetic
            // `__ofprefix("x")` argument (parser.expandOf, the `__dimchk`
            // pattern); expand the prefix against the live PDV here, the same
            // deferral and the same automatic/helper exemption as the special
            // lists beside it. Empty match: Table 4.5 settles only the matching
            // rule, so D-002 + the "special list matched no variables" precedent
            // above decide — a loud ERROR (rc 1: a typo'd prefix is the user's),
            // never a silent zero-argument call.
            if (arg.* == .call and std.ascii.eqlIgnoreCase(arg.call.name, "__ofprefix") and
                arg.call.args.len == 1 and arg.call.args[0] == .str)
            {
                const pfx = arg.call.args[0].str;
                var matched = false;
                for (self.pdv.vars.items) |v| {
                    if (isAutoVar(v.name)) continue;
                    if (std.ascii.startsWithIgnoreCase(v.name, pfx)) {
                        try argv.append(self.arena, v.value);
                        matched = true;
                    }
                }
                if (!matched) {
                    try self.diags.report(.err, 0, "OF variable list: the name prefix '{s}' matched no variables", .{pfx});
                    return Value.missing;
                }
                continue;
            }
            if (arg.* == .variable) if (specialList(arg.variable)) |kind| {
                for (self.pdv.vars.items) |v| {
                    if (isAutoVar(v.name)) continue;
                    const num = v.type == .num;
                    if (kind == .all or (kind == .numeric and num) or (kind == .character and !num))
                        try argv.append(self.arena, v.value);
                }
                continue;
            };
            try argv.append(self.arena, try self.eval(arg));
        }
        if (self.call_fn) |f| return f(self, c.name, argv.items);
        try self.diags.report(.err, 0, "function {s}() is not supported yet", .{c.name});
        return Value.missing;
    }

    // ── arithmetic (missing propagates) ──────────────────────────────────
    fn arith(self: *Evaluator, op: ast.BinOp, lv: Value, rv: Value) Error!Value {
        const x = try self.toNum(lv);
        const y = try self.toNum(rv);
        if (std.math.isNan(x) or std.math.isNan(y)) {
            // GAP-missgennote: arithmetic on a missing operand yields missing AND
            // logs SAS's note (Language Reference: Concepts p.110, Ex. 5.1). Fires too when the missing
            // came from an invalid char→num coercion just above — uniform rule:
            // an operand was missing, so the result is. Div-by-zero never reaches
            // here (its own note); comparisons don't route through arith.
            // ponytail: no "(N times) at (Line):(Column)" aggregation — one plain
            // NOTE per occurrence, like the GH#74 conversion notes.
            self.note("Missing values were generated as a result of performing an operation on missing values.", .{});
            return Value.missing;
        }
        const r = switch (op) {
            .add => x + y,
            .sub => x - y,
            .mul => x * y,
            .div => blk: {
                if (y == 0) {
                    // NOTE-invalidnumdataloc (GH#78): no "at line N column M"
                    // tail — AST expressions carry no source span, so the only
                    // printable position was a frozen 0/0 literal, which reads
                    // as a bug. An omitted position is honest; 0/0 was not.
                    self.note("Division by zero detected.", .{});
                    try self.setError();
                    return Value.missing; // reported here — not the NaN path below
                }
                break :blk x / y;
            },
            .pow => std.math.pow(f64, x, y), // neg base ^ fractional → NaN → missing
            else => unreachable,
        };
        // Overflow (±inf) and invalid (NaN) both collapse to SAS missing.
        // NOTE-overflownonote (tick183): overflow NOTES on the way to missing
        // — the same math-domain NOTE functions.zig's domErr emits — matching
        // the div-by-zero path just above (was the only silent numeric-error
        // path).
        if (std.math.isInf(r)) {
            self.note("{s}: argument out of domain (result set to missing)", .{@tagName(op)});
            return Value.missing;
        }
        // BUG-powdomainnote: an invalid pow (negative base ^ fractional
        // exponent → NaN) was the last SILENT domain error in this evaluator —
        // sqrt(-1)/log(-1) (functions.zig domErr), MOD-by-zero and
        // divide-by-zero all NOTE + set _ERROR_ on the same class. Match the
        // siblings exactly: same wording, _ERROR_=1, missing, keep going.
        if (std.math.isNan(r)) {
            self.note("{s}: argument out of domain (result set to missing)", .{@tagName(op)});
            try self.setError();
            return Value.missing;
        }
        return .{ .num = r };
    }

    // ── comparison (missing is lowest; never propagates) ─────────────────
    fn cmp(self: *Evaluator, a: Value, b: Value) Error!std.math.Order {
        // Two chars compare as blank-padded strings; anything else is numeric,
        // coercing a char operand to a number (SAS char-vs-num rule).
        if (a == .str and b == .str) return cmpStr(a.str, b.str);
        return cmpNum(try self.toNum(a), try self.toNum(b));
    }

    /// SAS automatic `_ERROR_`: an invalid char→num conversion or a division by
    /// zero inside an EXPRESSION sets it to 1, live in-step (Language Reference: Concepts p.110/111),
    /// exactly as the INPUT path in pdv.zig does (CHARNUM-errorvar) — without
    /// it the validation idiom `if _error_ then …` silently never fires
    /// (BUG-exprnoerrorvar). Plain PDV var; the executor resets it per iteration.
    /// pub: functions.zig routes its invalid-argument NOTEs through this same
    /// setter (MISC-fnseterror) — one _ERROR_ path for exprs and functions.
    pub fn setError(self: *Evaluator) Error!void {
        try self.pdv.set("_error_", .{ .num = 1 });
    }

    // ── coercions ────────────────────────────────────────────────────────
    fn toNum(self: *Evaluator, v: Value) Error!f64 {
        return switch (v) {
            .num => |x| x,
            .str => |s| {
                const trimmed = std.mem.trim(u8, s, " ");
                if (trimmed.len == 0) return std.math.nan(f64); // blank char → missing
                // A quoted special-missing token ('.K') coerces via the w. informat
                // to that special missing, not plain missing — so `x=.K` matches
                // `x='.K'` (GH#58). Try this before parseFloat; no invalid-value NOTE.
                if (Value.parseSpecialMissing(trimmed)) |sm| return sm.num;
                // SAS logs a NOTE on EVERY implicit char→num conversion (GH#74),
                // matching the char→num ASSIGNMENT note in pdv.zig (GH#9). Line 0
                // — AST nodes carry no source span (see `note` below).
                self.note("Character values have been converted to numeric values at the places given by: (Line):(Column).", .{});
                return pdv_mod.sasParseFloat(trimmed) orelse {
                    // Rejected by SAS's `w.` informat (unparsable, or a Zig-only
                    // syntax like 0x1F / 1_000): SAS emits BOTH the converted note
                    // (above) and this invalid-data note (matches pdv.zig's pair),
                    // and flags _ERROR_=1. Real SAS tails it "at line N column M."
                    // (Language Reference: Concepts Example Code 4.1 logs the sibling "Invalid character
                    // data … at line 53 column 7."), but no expression span exists
                    // here to fill N/M — GH#78: omit the position rather than print
                    // a frozen "line 0 column 0" (NOTE-invalidnumdataloc).
                    self.note("Invalid numeric data, '{s}'.", .{s});
                    try self.setError();
                    return std.math.nan(f64);
                };
            },
        };
    }

    /// `||` operand text: a bare char VARIABLE contributes its value PADDED to
    /// its declared length — fixed-length char vars carry their trailing blanks
    /// into concatenation (Language Reference: Concepts p.49: that is exactly why TRIM is needed;
    /// BUG-concatnopad). A literal/expression keeps its own width; a numeric
    /// converts BEST12 right-justified (BUG-numcharwidth, via toStr). The PDV
    /// truncates stored values to the declared length on assignment, so only
    /// padding is needed here, never truncation. ponytail: array ELEMENTS of a
    /// char array arrive as `.array_ref` (value only) and stay unpadded —
    /// resolve-and-pad them too if a fixture ever needs it.
    fn concatStr(self: *Evaluator, e: *const ast.Expr, v: Value) Error![]const u8 {
        const s = try self.toStr(v);
        if (e.* != .variable) return s;
        const i = self.pdv.indexOf(e.variable) orelse return s;
        const vr = self.pdv.vars.items[i];
        if (vr.type != .char or vr.len == 0 or s.len >= vr.len) return s;
        const out = try self.arena.alloc(u8, vr.len);
        @memcpy(out[0..s.len], s);
        @memset(out[s.len..], ' ');
        return out;
    }

    fn toStr(self: *Evaluator, v: Value) Error![]const u8 {
        return switch (v) {
            .str => |s| s,
            .num => |x| blk: {
                // SAS logs a NOTE on every implicit num→char conversion (GH#74),
                // same placeholder location as the char→num notes.
                self.note("Numeric values have been converted to character values at the places given by: (Line):(Column).", .{});
                // SAS num→char auto-conversion is BEST12. RIGHT-JUSTIFIED in a
                // 12-wide field (Language Reference: Concepts p.124): `n||"x"` → "           5x"
                // (BUG-numcharwidth). Missings keep their `.`/`.A`-`.Z` letter,
                // padded (ISS-specialmiss-tochar, via bestNumW inside numToChar).
                break :blk try pdv_mod.numToChar(self.arena, x, 12);
            },
        };
    }

    fn note(self: *Evaluator, comptime fmt: []const u8, args: anytype) void {
        // Best-effort: losing a NOTE under OOM is fine, the real error surfaces
        // at the next allocation. Line 0 — AST nodes carry no line yet.
        self.diags.report(.note, 0, fmt, args) catch {};
    }
};

fn boolVal(b: bool) Value {
    return .{ .num = if (b) 1 else 0 };
}

const ListKind = enum { numeric, character, all };

/// The `of` special variable lists, or null for an ordinary name.
fn specialList(name: []const u8) ?ListKind {
    const eqi = std.ascii.eqlIgnoreCase;
    if (eqi(name, "_numeric_")) return .numeric;
    if (eqi(name, "_character_")) return .character;
    if (eqi(name, "_all_")) return .all;
    return null;
}

/// Automatic / helper variables a special list must skip (they aren't data vars).
fn isAutoVar(name: []const u8) bool {
    const eqi = std.ascii.eqlIgnoreCase;
    return eqi(name, "_n_") or eqi(name, "_error_") or eqi(name, "_setobs_") or
        std.ascii.startsWithIgnoreCase(name, "first.") or std.ascii.startsWithIgnoreCase(name, "last.");
}

/// Member variables of an ARRAY declared over a special list (`_numeric_` /
/// `_character_` / `_all_`), resolved against the live PDV in declaration order —
/// data vars only, auto/BY-flag helpers skipped. The set is a runtime fact, so
/// array_ref / array_assign / dim all resolve it here (GH#48; mirrors the
/// `of _character_` handling in evalCall).
/// ponytail: expands against the WHOLE PDV, like `of _numeric_` and PROC SORT's
/// special lists (#26). SAS's exact rule is "vars of that type defined BEFORE the
/// array statement", so a same-type loop index / temp declared later is also
/// swept in — harmless for the common `do i=1 to dim(v); v[i]=…` pattern (i is
/// last, its stray write is invisible). Upgrade to source-position filtering if a
/// program's dim()/binding depends on excluding later-declared vars.
pub fn specialArrayNames(arena: std.mem.Allocator, pdv: *const pdv_mod.Pdv, kind: ast.SpecialArr) Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (pdv.vars.items) |v| {
        if (isAutoVar(v.name)) continue;
        const num = v.type == .num;
        const match = switch (kind) { .all => true, .numeric => num, .character => !num };
        if (match) try out.append(arena, v.name);
    }
    return out.toOwnedSlice(arena);
}

/// PERF-inlist: one element of a candidate IN/NOT-IN chain. `node` must be a
/// `.binary` whose op is `want` (`.eq` for IN, `.ne` for NOT-IN), comparing a
/// bare `.variable` against a FINITE `.num` literal. The variable must be the
/// same across every element (recorded in `var_name` on the first, compared
/// case-insensitively after). Appends the literal to `vals` and returns true;
/// returns false on ANY mismatch (wrong op, both-var, both-literal, non-finite
/// literal, or a different variable) → buildInSet bails, OR-chain runs unchanged.
fn collectInElem(node: *const ast.Expr, want: ast.BinOp, var_name: *?[]const u8, vals: *std.ArrayList(f64), arena: std.mem.Allocator) Error!bool {
    if (node.* != .binary or node.binary.op != want) return false;
    const b = node.binary;
    var vname: []const u8 = undefined;
    var lit: f64 = undefined;
    if (b.lhs.* == .variable and b.rhs.* == .num) {
        vname = b.lhs.variable;
        lit = b.rhs.num;
    } else if (b.rhs.* == .variable and b.lhs.* == .num) {
        vname = b.rhs.variable;
        lit = b.lhs.num;
    } else return false; // both-var, both-literal, or any other operand shape
    if (!std.math.isFinite(lit)) return false; // special-missing / NaN / inf never joins the set
    if (var_name.*) |prev| {
        if (!std.ascii.eqlIgnoreCase(prev, vname)) return false; // a second variable → not a single-var IN
    } else var_name.* = vname;
    try vals.append(arena, lit);
    return true;
}

fn cmpNum(a: f64, b: f64) std.math.Order {
    const am = std.math.isNan(a);
    const bm = std.math.isNan(b);
    // Missings sort below every real number; among themselves by SAS rank
    // (._ < . < .A < … < .Z), so special missings order and compare correctly.
    if (am and bm) return std.math.order(Value.missingRank(a), Value.missingRank(b));
    if (am) return .lt;
    if (bm) return .gt;
    if (a < b) return .lt;
    if (a > b) return .gt;
    return .eq;
}

fn cmpStr(a: []const u8, b: []const u8) std.math.Order {
    const n = @max(a.len, b.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const ca = if (i < a.len) a[i] else ' '; // shorter side padded with blanks
        const cb = if (i < b.len) b[i] else ' ';
        if (ca < cb) return .lt;
        if (ca > cb) return .gt;
    }
    return .eq;
}

// ── tests ────────────────────────────────────────────────────────────────

const t = std.testing;

/// Tiny arena-backed Expr builders so tests read like the SAS they model.
const B = struct {
    a: std.mem.Allocator,
    fn num(self: B, x: f64) *const ast.Expr {
        const e = self.a.create(ast.Expr) catch unreachable;
        e.* = .{ .num = x };
        return e;
    }
    fn str(self: B, s: []const u8) *const ast.Expr {
        const e = self.a.create(ast.Expr) catch unreachable;
        e.* = .{ .str = s };
        return e;
    }
    fn miss(self: B) *const ast.Expr {
        const e = self.a.create(ast.Expr) catch unreachable;
        e.* = .missing;
        return e;
    }
    fn vbl(self: B, name: []const u8) *const ast.Expr {
        const e = self.a.create(ast.Expr) catch unreachable;
        e.* = .{ .variable = name };
        return e;
    }
    fn bin(self: B, op: ast.BinOp, l: *const ast.Expr, r: *const ast.Expr) *const ast.Expr {
        const e = self.a.create(ast.Expr) catch unreachable;
        e.* = .{ .binary = .{ .op = op, .lhs = l, .rhs = r } };
        return e;
    }
    fn un(self: B, op: ast.UnOp, o: *const ast.Expr) *const ast.Expr {
        const e = self.a.create(ast.Expr) catch unreachable;
        e.* = .{ .unary = .{ .op = op, .operand = o } };
        return e;
    }
};

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    pdv: pdv_mod.Pdv = undefined,
    diags: diag.Diagnostics = undefined,

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
    }
    // Bind pdv/diags to the arena only once `self` is at its final address —
    // `arena.allocator()` captures `&self.arena`, so priming before the Fixture
    // stops moving would dangle.
    fn prime(self: *Fixture) void {
        const a = self.arena.allocator();
        self.pdv = pdv_mod.Pdv.init(a);
        self.diags = diag.Diagnostics.init(a);
    }
    fn ev(self: *Fixture) Evaluator {
        return .{ .arena = self.arena.allocator(), .pdv = &self.pdv, .diags = &self.diags };
    }
    fn b(self: *Fixture) B {
        return .{ .a = self.arena.allocator() };
    }
};

// ── typed constants ─────────────────────────────────────────────────────────
// Value conversions for the lexer's `'…'d/t/dt/b/x` literals. Each returns null
// on a malformed body (the lexer then keeps the plain string).
// ponytail: 4-digit years only (no yearcutoff), as elsewhere.

fn cdIsDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn monthNum(abbr: []const u8) ?i64 {
    const names = [_][]const u8{ "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" };
    for (names, 0..) |m, i| if (std.ascii.eqlIgnoreCase(abbr, m)) return @intCast(i + 1);
    return null;
}

/// Days from 1970-01-01 (Hinnant) then shifted to the SAS epoch (1960-01-01 is
/// SAS day 0; 1970-01-01 is SAS day 3653).
fn sasDate(y: i64, m: i64, d: i64) i64 {
    const yy = if (m <= 2) y - 1 else y;
    const era = @divFloor(if (yy >= 0) yy else yy - 399, 400);
    const yoe = yy - era * 400;
    const mp = if (m > 2) m - 3 else m + 9;
    const doy = @divTrunc(153 * mp + 2, 5) + d - 1;
    const doe = yoe * 365 + @divTrunc(yoe, 4) - @divTrunc(yoe, 100) + doy;
    return era * 146097 + doe - 719468 + 3653;
}

/// `ddMMMyyyy` → SAS date (days since 1960-01-01).
pub fn dateConst(s: []const u8) ?f64 {
    const str = std.mem.trim(u8, s, " ");
    var i: usize = 0;
    while (i < str.len and cdIsDigit(str[i])) i += 1;
    if (i == 0 or i + 3 > str.len) return null;
    const day = std.fmt.parseInt(i64, str[0..i], 10) catch return null;
    const mon = monthNum(str[i .. i + 3]) orelse return null;
    const year = std.fmt.parseInt(i64, str[i + 3 ..], 10) catch return null;
    return @floatFromInt(sasDate(year, mon, day));
}

/// `HH:MM[:SS][ ]?(AM|PM)?` → seconds since midnight (a SAS time value).
pub fn timeConst(s: []const u8) ?f64 {
    var str = std.mem.trim(u8, s, " ");
    var add12 = false;
    var force0 = false;
    if (str.len >= 2 and std.ascii.eqlIgnoreCase(str[str.len - 2 ..], "pm")) {
        add12 = true;
        str = std.mem.trim(u8, str[0 .. str.len - 2], " ");
    } else if (str.len >= 2 and std.ascii.eqlIgnoreCase(str[str.len - 2 ..], "am")) {
        force0 = true;
        str = std.mem.trim(u8, str[0 .. str.len - 2], " ");
    }
    var it = std.mem.splitScalar(u8, str, ':');
    var h = std.fmt.parseInt(i64, std.mem.trim(u8, it.next() orelse return null, " "), 10) catch return null;
    const m = std.fmt.parseInt(i64, std.mem.trim(u8, it.next() orelse "0", " "), 10) catch return null;
    const sec = std.fmt.parseFloat(f64, std.mem.trim(u8, it.next() orelse "0", " ")) catch return null;
    if (add12 and h < 12) h += 12;
    if (force0 and h == 12) h = 0;
    return @as(f64, @floatFromInt(h * 3600 + m * 60)) + sec;
}

/// `ddMMMyyyy:HH:MM:SS` → SAS datetime (seconds since 1960-01-01 00:00).
pub fn datetimeConst(s: []const u8) ?f64 {
    const str = std.mem.trim(u8, s, " ");
    const c = std.mem.indexOfScalar(u8, str, ':') orelse return null;
    const d = dateConst(str[0..c]) orelse return null;
    const tm = timeConst(str[c + 1 ..]) orelse return null;
    return d * 86400 + tm;
}

/// Binary-digit string → its numeric value (`'1010'b` → 10).
pub fn bitConst(s: []const u8) ?f64 {
    var v: u64 = 0;
    for (s) |ch| {
        if (ch == ' ') continue;
        if (ch != '0' and ch != '1') return null;
        v = v * 2 + (ch - '0');
    }
    return @floatFromInt(v);
}

/// Hex-pair string → the raw bytes it encodes (`'534153'x` → "SAS").
pub fn hexConst(arena: std.mem.Allocator, s: []const u8) ?[]const u8 {
    if (s.len == 0 or s.len % 2 != 0) return null;
    const out = arena.alloc(u8, s.len / 2) catch return null;
    var k: usize = 0;
    while (k < s.len) : (k += 2) {
        const hi = std.fmt.charToDigit(s[k], 16) catch return null;
        const lo = std.fmt.charToDigit(s[k + 1], 16) catch return null;
        out[k / 2] = hi * 16 + lo;
    }
    return out;
}

test "typed-constant conversions (G-const)" {
    try t.expectEqual(@as(f64, 21915), dateConst("01JAN2020").?); // 01JAN2020
    try t.expectEqual(@as(f64, 49530), timeConst("13:45:30").?); // 13*3600+45*60+30
    try t.expectEqual(@as(f64, 77119), timeConst("9:25:19pm").?); // 21:25:19
    try t.expectEqual(@as(f64, 60), datetimeConst("01JAN1960:00:01:00").?);
    try t.expectEqual(@as(f64, 10), bitConst("1010").?);
    try t.expect(dateConst("nope") == null);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try t.expectEqualStrings("SAS", hexConst(arena.allocator(), "534153").?);
    try t.expect(hexConst(arena.allocator(), "5G") == null);
}

fn fixture() Fixture {
    // No allocator() call here — the returned value is moved by the caller.
    return .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
}

test "arithmetic and precedence-free operator semantics" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var e = f.ev();
    const b = f.b();

    // 2 + 3 * 4  (tree already shaped by the parser)
    const expr = b.bin(.add, b.num(2), b.bin(.mul, b.num(3), b.num(4)));
    try t.expectEqual(@as(f64, 14), (try e.eval(expr)).num);

    // 2 ** 3 = 8
    try t.expectEqual(@as(f64, 8), (try e.eval(b.bin(.pow, b.num(2), b.num(3)))).num);

    // unary minus
    try t.expectEqual(@as(f64, -5), (try e.eval(b.un(.neg, b.num(5)))).num);
}

test "missing propagates through arithmetic, div-by-zero and bad-pow give missing" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var e = f.ev();
    const b = f.b();

    try t.expect((try e.eval(b.bin(.add, b.miss(), b.num(1)))).isMissing()); // . + 1 = .
    try t.expect((try e.eval(b.bin(.div, b.num(1), b.num(0)))).isMissing()); // 1/0 = .
    try t.expect((try e.eval(b.bin(.pow, b.num(-1), b.num(0.5)))).isMissing()); // sqrt(-1) = .
    try t.expect(f.diags.count() > 0); // div-by-zero left a NOTE
}

test "NOTE-overflownonote: arithmetic overflow gives missing WITH a NOTE" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var e = f.ev();
    const b = f.b();

    // 2**1024 overflows → missing + the math-domain NOTE (was silent).
    try t.expect((try e.eval(b.bin(.pow, b.num(2), b.num(1024)))).isMissing());
    // 1e308*10 overflows → same.
    try t.expect((try e.eval(b.bin(.mul, b.num(1e308), b.num(10)))).isMissing());
    try t.expectEqual(@as(usize, 2), f.diags.count());
    try t.expectEqualStrings("pow: argument out of domain (result set to missing)", f.diags.list.items[0].message);
    try t.expectEqualStrings("mul: argument out of domain (result set to missing)", f.diags.list.items[1].message);

    // normal ops: unchanged, no spurious NOTE.
    try t.expectEqual(@as(f64, 1024), (try e.eval(b.bin(.pow, b.num(2), b.num(10)))).num);
    try t.expectEqual(@as(f64, 3), (try e.eval(b.bin(.div, b.num(6), b.num(2)))).num);
    try t.expectEqual(@as(usize, 2), f.diags.count());

    // NaN (invalid pow) NOTES too now (BUG-powdomainnote — same wording as
    // domErr, _ERROR_=1); div-by-zero keeps its own NOTE.
    try t.expect((try e.eval(b.bin(.pow, b.num(-1), b.num(0.5)))).isMissing());
    try t.expectEqual(@as(usize, 3), f.diags.count());
    try t.expectEqualStrings("pow: argument out of domain (result set to missing)", f.diags.list.items[2].message);
    try t.expect((try e.eval(b.bin(.div, b.num(6), b.num(0)))).isMissing());
    try t.expectEqual(@as(usize, 4), f.diags.count());
    try t.expectEqualStrings("Division by zero detected.", f.diags.list.items[3].message);
}

test "BUG-powdomainnote: invalid pow NOTES + sets _ERROR_ like sqrt(-1)/MOD-by-zero" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var e = f.ev();
    const b = f.b();

    // (-1)**0.5 → missing WITH the domain NOTE (was silent — the only domain
    // error class in this evaluator that said nothing).
    try t.expect((try e.eval(b.bin(.pow, b.num(-1), b.num(0.5)))).isMissing());
    try t.expectEqual(@as(usize, 1), f.diags.count());
    try t.expectEqualStrings("pow: argument out of domain (result set to missing)", f.diags.list.items[0].message);
    // _ERROR_ = 1, same as functions.zig domErr (sqrt/log/MOD-by-zero).
    try t.expectEqual(@as(f64, 1), (f.pdv.get("_error_") orelse unreachable).num);
    // a NOTE, not an ERROR — execution continues; a later valid pow is fine.
    try t.expect(!f.diags.hasErrors());
    try t.expectEqual(@as(f64, 8), (try e.eval(b.bin(.pow, b.num(2), b.num(3)))).num);
}

test "comparisons yield 1/0; missing is lowest, not propagated" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var e = f.ev();
    const b = f.b();

    try t.expectEqual(@as(f64, 1), (try e.eval(b.bin(.gt, b.num(5), b.num(3)))).num);
    try t.expectEqual(@as(f64, 0), (try e.eval(b.bin(.gt, b.num(3), b.num(5)))).num);
    // missing sorts below everything, and the result is a real 0/1
    try t.expectEqual(@as(f64, 1), (try e.eval(b.bin(.lt, b.miss(), b.num(5)))).num);
    try t.expectEqual(@as(f64, 1), (try e.eval(b.bin(.eq, b.miss(), b.miss()))).num);
    // blank-padded string equality: "abc" = "abc "
    try t.expectEqual(@as(f64, 1), (try e.eval(b.bin(.eq, b.str("abc"), b.str("abc ")))).num);
    try t.expectEqual(@as(f64, 1), (try e.eval(b.bin(.lt, b.str("abc"), b.str("abd")))).num);
}

test "logical and/or/not over SAS truthiness" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var e = f.ev();
    const b = f.b();

    try t.expectEqual(@as(f64, 0), (try e.eval(b.bin(.@"and", b.num(1), b.num(0)))).num);
    try t.expectEqual(@as(f64, 1), (try e.eval(b.bin(.@"or", b.num(0), b.num(7)))).num);
    try t.expectEqual(@as(f64, 1), (try e.eval(b.un(.not, b.miss()))).num); // NOT . = 1
    try t.expectEqual(@as(f64, 0), (try e.eval(b.un(.not, b.num(3)))).num);
}

test "concat coerces, variables resolve from the PDV, char→num coercion" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var e = f.ev();
    const b = f.b();

    // "Jane" || " " || "Doe"
    const name = b.bin(.concat, b.bin(.concat, b.str("Jane"), b.str(" ")), b.str("Doe"));
    try t.expectEqualStrings("Jane Doe", (try e.eval(name)).str);

    // variable lookup (case-insensitive via PDV); unknown var → missing
    try f.pdv.set("Age", .{ .num = 40 });
    try t.expectEqual(@as(f64, 42), (try e.eval(b.bin(.add, b.vbl("AGE"), b.num(2)))).num);
    try t.expect((try e.eval(b.vbl("nope"))).isMissing());

    // char used in arithmetic auto-converts: "10" + 5 = 15
    try t.expectEqual(@as(f64, 15), (try e.eval(b.bin(.add, b.str("10"), b.num(5)))).num);

    // numeric used in concat auto-converts BEST12. RIGHT-JUSTIFIED in a 12-wide
    // field (Language Reference: Concepts p.124, BUG-numcharwidth): 14 || "!" = "          14!"
    try t.expectEqualStrings("          14!", (try e.eval(b.bin(.concat, b.num(14), b.str("!")))).str);
    // a missing pads too, keeping its `.` letter
    try t.expectEqualStrings("           .x", (try e.eval(b.bin(.concat, b.miss(), b.str("x")))).str);
}

test "concat pads a char VARIABLE to its declared length (BUG-concatnopad)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var e = f.ev();
    const b = f.b();

    // length t $5; t="fox" — stored unpadded, declared width 5
    const ti = try f.pdv.declare("t", .char);
    f.pdv.vars.items[ti].len = 5;
    try f.pdv.set("t", .{ .str = "fox" });

    // t || "!" → "fox  !" (SAS pads the variable; the literal keeps its width)
    try t.expectEqualStrings("fox  !", (try e.eval(b.bin(.concat, b.vbl("t"), b.str("!")))).str);
    // "!" || t → "!fox  " (padding is positional)
    try t.expectEqualStrings("!fox  ", (try e.eval(b.bin(.concat, b.str("!"), b.vbl("t")))).str);
    // var || var: both pad — length a $3 b $3; a="x"; b="y" → "x  y  "
    const ai = try f.pdv.declare("a", .char);
    f.pdv.vars.items[ai].len = 3;
    try f.pdv.set("a", .{ .str = "x" });
    const bi = try f.pdv.declare("bb", .char);
    f.pdv.vars.items[bi].len = 3;
    try f.pdv.set("bb", .{ .str = "y" });
    try t.expectEqualStrings("x  y  ", (try e.eval(b.bin(.concat, b.vbl("a"), b.vbl("bb")))).str);
    // a NO-declared-length char var keeps its raw stored value
    try f.pdv.set("plain", .{ .str = "xy" });
    try t.expectEqualStrings("xy!", (try e.eval(b.bin(.concat, b.vbl("plain"), b.str("!")))).str);
    // an all-blank char var contributes its full declared width of blanks
    try f.pdv.set("t", .{ .str = "" });
    try t.expectEqualStrings("     !", (try e.eval(b.bin(.concat, b.vbl("t"), b.str("!")))).str);
}

test "array subscript: out-of-range is a SAS ERROR that aborts the step (BUG-arrayoorerror)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var e = f.ev();
    const a = f.arena.allocator();
    const b = f.b();

    try f.pdv.set("x1", .{ .num = 10 });
    try f.pdv.set("x2", .{ .num = 20 });
    const elems: []const []const u8 = &.{ "x1", "x2" };
    const ref = struct {
        fn make(al: std.mem.Allocator, els: []const []const u8, idx: *const ast.Expr) *const ast.Expr {
            const ex = al.create(ast.Expr) catch unreachable;
            ex.* = .{ .array_ref = .{ .name = "a", .elements = els, .index = idx } };
            return ex;
        }
    }.make;

    // in-range reads are unchanged
    try t.expectEqual(@as(f64, 20), (try e.eval(ref(a, elems, b.num(2)))).num);
    // huge/negative/zero subscripts: ERROR + ExecError, never a @intFromFloat panic
    try t.expectError(error.ExecError, e.eval(ref(a, elems, b.num(1e300))));
    try t.expectError(error.ExecError, e.eval(ref(a, elems, b.num(-1e300))));
    try t.expectError(error.ExecError, e.eval(ref(a, elems, b.num(0))));
    // the ERROR is captured in diagnostics (no spawned abort), _ERROR_ flagged
    try t.expect(f.diags.hasErrors());
    try t.expectEqual(@as(f64, 1), f.pdv.get("_error_").?.num);
    // a MISSING (NaN) subscript is out of range too — fails loud, not soft
    // (BUG-arraysubmissing): a missing accumulator key must halt, not silently
    // read/write missing. Previously exempted; now routed through subscriptOor.
    try t.expectError(error.ExecError, e.eval(ref(a, elems, b.miss())));
    try t.expect(f.diags.hasErrors());
    try t.expectEqual(@as(f64, 1), f.pdv.get("_error_").?.num);
    // eval itself latches no state: in-range still evaluates afterwards
    try t.expectEqual(@as(f64, 10), (try e.eval(ref(a, elems, b.num(1)))).num);
}

test "unset call hook reports unsupported and yields missing" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var e = f.ev();
    const a = f.arena.allocator();

    const args = a.alloc(ast.Expr, 1) catch unreachable;
    args[0] = .{ .num = 1 };
    const call = a.create(ast.Expr) catch unreachable;
    call.* = .{ .call = .{ .name = "sum", .args = args } };

    try t.expect((try e.eval(call)).isMissing());
    try t.expect(f.diags.hasErrors());
}

// GAP-ofcolonprefix test hook: records the argv the OF-prefix expansion built.
var ofprefix_last_n: usize = undefined;
fn ofprefixEcho(ev: *Evaluator, name: []const u8, args: []const Value) Error!Value {
    _ = ev;
    _ = name;
    var s: f64 = 0;
    for (args) |v| s += v.num;
    ofprefix_last_n = args.len;
    return .{ .num = s };
}

test "GAP-ofcolonprefix: __ofprefix expands against the live PDV; empty match is a loud ERROR" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var e = f.ev();
    e.call_fn = &ofprefixEcho;
    const a = f.arena.allocator();
    const mk = struct { // sum(__ofprefix(pfx) [, var])
        fn f2(al: std.mem.Allocator, pfx: []const u8, extra: ?[]const u8) *const ast.Expr {
            const pargs = al.alloc(ast.Expr, 1) catch unreachable;
            pargs[0] = .{ .str = pfx };
            const sargs = al.alloc(ast.Expr, if (extra == null) 1 else 2) catch unreachable;
            sargs[0] = .{ .call = .{ .name = "__ofprefix", .args = pargs } };
            if (extra) |nm| sargs[1] = .{ .variable = nm };
            const c = al.create(ast.Expr) catch unreachable;
            c.* = .{ .call = .{ .name = "sum", .args = sargs } };
            return c;
        }
    }.f2;

    try f.pdv.set("x1", .{ .num = 10 });
    try f.pdv.set("X2", .{ .num = 20 }); // case-insensitive prefix match
    try f.pdv.set("y", .{ .num = 99 }); // not swept in
    try f.pdv.set("_error_", .{ .num = 1 }); // automatic: exempt even under `_:`

    // sum(of x:) → x1+X2 = 30 across two expanded args; y untouched
    try t.expectEqual(@as(f64, 30), (try e.eval(mk(a, "x", null))).num);
    try t.expectEqual(@as(usize, 2), ofprefix_last_n);
    // mixed with a plain arg: sum(of x: y) → 129
    try t.expectEqual(@as(f64, 129), (try e.eval(mk(a, "x", "y"))).num);
    try t.expectEqual(@as(usize, 3), ofprefix_last_n);
    // `_:` matches only the _error_ automatic (exempt) → loud ERROR + missing
    try t.expect((try e.eval(mk(a, "_", null))).isMissing());
    try t.expect(f.diags.hasErrors());
    try t.expect(std.mem.indexOf(u8, f.diags.list.items[f.diags.count() - 1].message, "matched no variables") != null);

    // an ordinary no-match prefix: same loud ERROR (rc 1 — no markGap)
    var f2 = fixture();
    defer f2.deinit();
    f2.prime();
    var e2 = f2.ev();
    e2.call_fn = &ofprefixEcho;
    try f2.pdv.set("y", .{ .num = 1 });
    try t.expect((try e2.eval(mk(f2.arena.allocator(), "zz", null))).isMissing());
    try t.expect(f2.diags.hasErrors());

    // evaluated AS the call (the CALL-statement path, args evaluated singly)
    // it is a loud GAP error, never a fabricated missing
    const a2 = f2.arena.allocator();
    const pargs = a2.alloc(ast.Expr, 1) catch unreachable;
    pargs[0] = .{ .str = "y" };
    const direct = a2.create(ast.Expr) catch unreachable;
    direct.* = .{ .call = .{ .name = "__ofprefix", .args = pargs } };
    try t.expectError(error.ExecError, e2.eval(direct));
}

test "GH#74: implicit conversions in an expression log the SAS NOTE" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var e = f.ev();
    const b = f.b();

    // char→num in an expression: "123" * 1 → converted note, valid parse (case 1)
    _ = try e.eval(b.bin(.mul, b.str("123"), b.num(1)));
    try t.expectEqual(@as(usize, 1), f.diags.count());
    try t.expect(std.mem.indexOf(u8, f.diags.list.items[0].message, "converted to numeric") != null);

    // unparsable char→num: converted note + invalid-data note, then the
    // missing-generated note (GAP-missgennote — the mul's operand is missing)
    _ = try e.eval(b.bin(.mul, b.str("abc"), b.num(1)));
    try t.expectEqual(@as(usize, 4), f.diags.count());
    try t.expect(std.mem.indexOf(u8, f.diags.list.items[2].message, "Invalid numeric data, 'abc'") != null);
    try t.expect(std.mem.indexOf(u8, f.diags.list.items[3].message, "Missing values were generated") != null);

    // num→char in an expression: 42 || "x" → converted-to-char note (case 2)
    _ = try e.eval(b.bin(.concat, b.num(42), b.str("x")));
    try t.expectEqual(@as(usize, 5), f.diags.count());
    try t.expect(std.mem.indexOf(u8, f.diags.list.items[4].message, "converted to character") != null);
}

test "NOTE-invalidnumdataloc: no frozen 'line 0 column 0' in the rendered NOTE (GH#78)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var e = f.ev();
    const b = f.b();

    // AST expressions carry no source span, so these NOTEs have no honest
    // position to print — they must OMIT it, not freeze 0/0 into the text.
    _ = try e.eval(b.bin(.mul, b.str("abc"), b.num(1)));
    try t.expectEqualStrings("Invalid numeric data, 'abc'.", f.diags.list.items[1].message);
    _ = try e.eval(b.bin(.div, b.num(1), b.num(0)));
    try t.expectEqualStrings("Division by zero detected.", f.diags.list.items[3].message);
    // The RENDERED log: plain "NOTE: …" — no "(L0)" tag, no position text.
    const log = try f.diags.render();
    try t.expect(std.mem.indexOf(u8, log, "NOTE: Invalid numeric data, 'abc'.\n") != null);
    try t.expect(std.mem.indexOf(u8, log, "NOTE: Division by zero detected.\n") != null);
    try t.expect(std.mem.indexOf(u8, log, "(L0") == null);
    try t.expect(std.mem.indexOf(u8, log, "column 0") == null);
}

test "GAP-missgennote: arithmetic on a missing operand logs SAS's NOTE" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var e = f.ev();
    const b = f.b();
    const want = "Missing values were generated as a result of performing an operation on missing values.";

    // y = . + 3 → missing, one NOTE (captured diagnostics)
    try t.expect((try e.eval(b.bin(.add, b.miss(), b.num(3)))).isMissing());
    try t.expectEqual(@as(usize, 1), f.diags.count());
    try t.expectEqualStrings(want, f.diags.list.items[0].message);

    // x * missing-variable → missing, second NOTE
    try f.pdv.set("x", Value.missing);
    try t.expect((try e.eval(b.bin(.mul, b.num(2), b.vbl("x")))).isMissing());
    try t.expectEqual(@as(usize, 2), f.diags.count());
    try t.expectEqualStrings(want, f.diags.list.items[1].message);

    // both operands present → silent
    try t.expectEqual(@as(f64, 5), (try e.eval(b.bin(.add, b.num(2), b.num(3)))).num);
    try t.expectEqual(@as(usize, 2), f.diags.count());
}

test "BUG-exprnoerrorvar: invalid conversion / div-by-zero in an expression set _ERROR_=1" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var e = f.ev();
    const b = f.b();

    // executor resets _ERROR_ to 0 at the top of each iteration; model that.
    try f.pdv.set("_error_", .{ .num = 0 });
    _ = try e.eval(b.bin(.mul, b.str("abc"), b.num(1))); // invalid char→num
    try t.expectEqual(@as(f64, 1), f.pdv.get("_error_").?.num);

    try f.pdv.set("_error_", .{ .num = 0 });
    _ = try e.eval(b.bin(.div, b.num(5), b.num(0))); // division by zero
    try t.expectEqual(@as(f64, 1), f.pdv.get("_error_").?.num);

    // valid conversion does NOT flag it
    try f.pdv.set("_error_", .{ .num = 0 });
    _ = try e.eval(b.bin(.mul, b.str("12"), b.num(1)));
    try t.expectEqual(@as(f64, 0), f.pdv.get("_error_").?.num);
}

test "special missings order: ._ < . < .A < .Z < number (G-specialmiss)" {
    const V = Value;
    try t.expect(cmpNum(V.specialMissing('_').num, V.missing.num) == .lt);
    try t.expect(cmpNum(V.missing.num, V.specialMissing('A').num) == .lt);
    try t.expect(cmpNum(V.specialMissing('A').num, V.specialMissing('Z').num) == .lt);
    try t.expect(cmpNum(V.specialMissing('Z').num, 5) == .lt);
    try t.expect(cmpNum(V.specialMissing('A').num, V.specialMissing('A').num) == .eq);
}
