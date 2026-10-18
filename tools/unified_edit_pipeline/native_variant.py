"""Strict read-only decoder for the data-only Godot Variant subset in checkpoints.

No object construction, execution or unknown-type substitution is permitted.
Packed fields stay as memoryviews of the original container payload.
"""
import struct


class VariantReader:
    def __init__(self, data):
        self.data = memoryview(data)
        self.offset = 0

    def take(self, count):
        if count < 0 or self.offset+count > len(self.data):
            raise ValueError("Truncated Variant data")
        value = self.data[self.offset:self.offset+count]
        self.offset += count
        return value

    def unpack(self, fmt):
        return struct.unpack(fmt, self.take(struct.calcsize(fmt)))[0]

    def align(self):
        padding = (-self.offset) % 4
        if any(self.take(padding)):
            raise ValueError("Nonzero Variant padding")

    def string(self):
        length = self.unpack("<I")
        value = bytes(self.take(length)).decode("utf-8")
        self.align()
        return value

    def value(self, depth=0):
        if depth > 64:
            raise ValueError("Variant nesting limit")
        tag = self.unpack("<I")
        kind, flags = tag & 0xffff, tag >> 16
        if kind == 0 and flags == 0:
            return None
        if kind == 1 and flags == 0:
            raw = self.unpack("<I")
            if raw > 1:
                raise ValueError("Invalid Variant bool")
            return bool(raw)
        if kind == 2 and flags in (0, 1):
            return self.unpack("<q" if flags else "<i")
        if kind == 3 and flags in (0, 1):
            return self.unpack("<d" if flags else "<f")
        if kind in (4, 21) and flags == 0:
            return self.string()
        if kind in (27, 28) and flags == 0:
            count = self.unpack("<I")
            if count > 1000000:
                raise ValueError("Variant container size limit")
            if kind == 28:
                return [self.value(depth+1) for _ in range(count)]
            result = {}
            for _ in range(count):
                key = self.value(depth+1)
                if key in result:
                    raise ValueError("Duplicate Variant dictionary key")
                result[key] = self.value(depth+1)
            return result
        if kind == 29 and flags == 0:
            count = self.unpack("<I")
            value = self.take(count)
            self.align()
            return value
        formats = {30: "i", 31: "q", 32: "f", 33: "d"}
        if kind in formats and flags == 0:
            count = self.unpack("<I")
            if count > 1000000:
                raise ValueError("Packed Variant count limit")
            fmt = formats[kind]
            return list(struct.unpack("<"+str(count)+fmt, self.take(count*struct.calcsize(fmt))))
        raise ValueError(f"Unsupported Variant type {kind}, flags {flags}, at {self.offset-4}")

    def document(self):
        value = self.value()
        if self.offset != len(self.data):
            raise ValueError("Trailing Variant data")
        return value
