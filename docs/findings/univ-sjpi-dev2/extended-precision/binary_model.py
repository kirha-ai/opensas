"""Exact normal-range binary significand arithmetic for the SJPI discriminator.

Fractions represent operations exactly before explicit round-to-nearest/even.
This models 53/64-bit significands and declared binary64 spills, not an x87
instruction decoder, unknown compiler register allocation, or FPU exceptions.
Every retained input/intermediate is finite and in the normal exponent range.
"""
from fractions import Fraction as F

ORDERS = (
    'center_div', 'center_normalize', 'center_inverse',
    'absolute_div', 'absolute_inverse',
)
STORAGE = (
    'binary64', 'extended64', 'extended64_step_store',
    'extended64_input_store', 'extended64_q_store', 'extended64_each_store',
)
CONVERSIONS = ('trunc_after_half', 'spill_half_then_trunc', 'nearest_even')


def power2(exponent):
    return F(1 << exponent) if exponent >= 0 else F(1, 1 << -exponent)


def exponent2(value):
    value = abs(F(value))
    if not value:
        raise ValueError('zero has no normal binade')
    exponent = value.numerator.bit_length() - value.denominator.bit_length()
    if value < power2(exponent):
        exponent -= 1
    return exponent


def nearest_integer(value):
    value = F(value)
    sign = -1 if value < 0 else 1
    value = abs(value)
    quotient, remainder = divmod(value.numerator, value.denominator)
    twice = 2 * remainder
    if twice > value.denominator or (twice == value.denominator and quotient % 2):
        quotient += 1
    return sign * quotient


def rounded(value, precision):
    value = F(value)
    if not value:
        return F(0)
    unit = power2(exponent2(value) - precision + 1)
    return nearest_integer(value / unit) * unit


def ulp(value, precision):
    return power2(exponent2(value) - precision + 1)


class Arithmetic:
    def __init__(self, storage):
        assert storage in STORAGE
        self.storage = storage
        self.precision = 53 if storage == 'binary64' else 64

    def op(self, operation, a, b):
        a, b = F(a), F(b)
        if operation == '+':
            exact = a + b
        elif operation == '-':
            exact = a - b
        elif operation == '*':
            exact = a * b
        elif operation == '/':
            exact = a / b
        else:
            raise ValueError(operation)
        result = rounded(exact, self.precision)
        if self.storage == 'extended64_each_store':
            result = rounded(result, 53)
        return result

    def named(self, name, value):
        spills = {
            'extended64_step_store': {'step'},
            'extended64_input_store': {'span', 'centered', 'step', 'inverse'},
            'extended64_q_store': {'q'},
        }
        if name in spills.get(self.storage, set()):
            return rounded(value, 53)
        return value

    def coordinate(self, x, low, high, order):
        assert order in ORDERS
        x, low, high = map(F, (x, low, high))
        span = self.named('span', self.op('-', high, low))
        centered = self.named('centered', self.op('-', x, low))
        step = self.named('step', self.op('/', span, 200))
        if order == 'center_div':
            q = self.op('/', centered, step)
        elif order == 'center_normalize':
            q = self.op('*', self.op('/', centered, span), 200)
        elif order == 'center_inverse':
            inverse = self.named('inverse', self.op('/', 1, step))
            q = self.op('*', centered, inverse)
        elif order == 'absolute_div':
            q = self.op('-', self.op('/', x, step), self.op('/', low, step))
        else:
            inverse = self.named('inverse', self.op('/', 1, step))
            q = self.op('-', self.op('*', x, inverse), self.op('*', low, inverse))
        return self.named('q', q)

    def integer_bin(self, q, conversion):
        assert conversion in CONVERSIONS
        if conversion == 'nearest_even':
            return nearest_integer(q)
        shifted = self.op('+', q, F(1, 2))
        if conversion == 'spill_half_then_trunc':
            shifted = rounded(shifted, 53)
        # Coordinates here are positive, so truncation equals floor. Keep the
        # signed definition explicit, as used by an integer conversion.
        sign = -1 if shifted < 0 else 1
        return sign * (abs(shifted.numerator) // shifted.denominator)


def self_test():
    for p in (53, 64):
        half = power2(-p)
        assert rounded(1 + half, p) == 1
        assert rounded(1 + 3 * half, p) == 1 + power2(2-p)
        assert rounded(-1 - half, p) == -1
        assert rounded(-1 - 3 * half, p) == -1 - power2(2-p)
        assert rounded(F(1, 3), p) != F(1, 3)
        assert rounded(rounded(F(1, 3), p), p) == rounded(F(1, 3), p)
    # Retaining the extended sum and spilling it to binary64 genuinely differ.
    q = F(125, 2) - power2(-55)
    a = Arithmetic('extended64')
    assert a.integer_bin(q, 'trunc_after_half') == 62
    assert a.integer_bin(q, 'spill_half_then_trunc') == 63
    assert nearest_integer(F(125, 2)) == 62
    assert nearest_integer(F(127, 2)) == 64
