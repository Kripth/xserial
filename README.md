xserial
=======

[![DUB Package](https://img.shields.io/dub/v/xserial.svg)](https://code.dlang.org/packages/xserial)
[![codecov](https://codecov.io/gh/Kripth/xserial/branch/master/graph/badge.svg)](https://codecov.io/gh/Kripth/xserial)
[![Build Status](https://travis-ci.org/Kripth/xserial.svg?branch=master)](https://travis-ci.org/Kripth/xserial)

Binary serialization and deserialization library that uses [xbuffer](https://github.com/Kripth/xbuffer).

```d
import xserial;

assert(true.serialize() == [1]);
assert(deserialize!bool([0]) == false);

assert(12.serialize!(Endian.bigEndian)() == [0, 0, 0, 12]);
assert(deserialize!(int, Endian.littleEndian)([44, 0, 0, 0]) == 44);

assert([1, 2, 3].serialize!(Endian.littleEndian, ushort)() == [3, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0]);
assert(deserialize!(ushort[], Endian.bigEndian, uint)([0, 0, 0, 2, 0, 12, 0, 44]) == [12, 44]);

struct Foo { ubyte a, b, c; }
Foo foo = Foo(1, 2, 4);
assert(foo.serialize.deserialize!Foo == foo);
```

Usage
-----

## Serialization

The `serialize` template is publicly imported in the `xserial` module. It takes, optionally, the endianness and the array length to be used for serializing; if not provided the system's endianness is used and `size_t` is used to encode arrays' lengths.

The first runtime argument is always the value that needs to be serialized and the second optional argument is a [xbuffer](https://github.com/Kripth/xbuffer)'s `Buffer`, that can be used when serializing more than one type by reusing the buffer.

The `serialize` template always returns an array of unsigned bytes.

```
ubyte[] serialize!(Endian endianness=std.system.endian, L=size_t, T)(T value, Buffer buffer=new Buffer(64));
```

## Deserialization

The `deserialize` template has similar arguments as the `serialize` template, except the first runtime argument, the value to serialize, is passed as a type as the first compile-time argument.

It returns an instance of the type passed at compile-time or throws a `BufferOverflowException` when there's not enough data to read.

```
T deserialize!(T, Endian endianness=std.system.endian, L=size_t)(Buffer buffer);
T deserialize!(T, Endian endianness=std.system.endian, L=size_t)(in ubyte[] buffer);
```

## Attributes

In structs and classes all public variables are serialized and deserialized. How they are serialized can be changed using attributes.

One attribute for each group can be used on a variable.

### Exclusion

Exclusion attributes indicate whether to serialize and deserialize a varible.

#### @Exclude
Excludes the variable from being serialized and deserialized.

#### @EncodeOnly
Excludes the variable from being deserialized.

#### @DecodeOnly
Excludes the variable from being serialized.

### Conditional

Conditional attributes indicate when to serialize and deserialize a variable.

#### @Condition(string)
Only serializes and deserializes the variable when the condition is true.
```d
struct Test {

    ubyte a;
    @Condition("a == 0") ubyte b;

}

assert(Test(0, 1).serialize() == [0, 1]);
assert(Test(1, 0).serialize() == [1]);
```

### Type encoding

Type encoding attributes indicate how to serialize and deserialize a variable.

#### @BigEndian

Indicates that the variable (or the elements of the array) are always encoded as big-endian.

#### @LittleEndian

Indicates that the variable (or the elements of the array) are always encoded as little-endian.

#### @Var

Indicates that the variable (or the elements of the array) are always encoded as [Google varint](https://developers.google.com/protocol-buffers/docs/encoding).

### Array's Length

Array's length attributes indicate how to serialize and deserialize the length of an array variable.

#### @Length!(type)

Indicates that the variable's length should be serialized and deserialized as the given type.

#### @EndianLength!(type)(Endian)

Like @Length indicates that the variable's length should be serialized and deserialized as the given type, with the addition that the variable's length is also serialized and deserialized with the given endianness.
```d
struct Test {

    @EndianLength!ushort(Endian.bigEndian) ubyte[] a;

}

assert(Test([1, 2, 3]).serialize() == [0, 3, 1, 2, 3]);
assert(Test([1, 2, 3]).serialize!(Endian.littleEndian, uint)() == [0, 3, 1, 2, 3]);
```

#### @NoLength

Indicates that the variable's length should not be encoded. This attribute should only be used on the last field of the struct/class.
When deserializing a variable with this attribute data is read until a `BufferOverflowException` is thrown.
