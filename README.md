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
