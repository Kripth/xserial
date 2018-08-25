module xserial.serial;

import std.system : Endian, endian;
import std.traits : isArray, isDynamicArray, isStaticArray, isAssociativeArray, ForeachType, KeyType, ValueType, isIntegral, isFloatingPoint, isSomeChar, isType, isCallable, isPointer, hasUDA, getUDAs;
import std.typecons : isTuple;

import xbuffer.buffer : canSwapEndianness, Buffer, BufferOverflowException;
import xbuffer.memory : xalloc, xfree;
import xbuffer.varint : isVar;

import xserial.attribute;

/**
 * Serializes some data.
 */
ubyte[] serialize(Endian endianness, L, Endian lengthEndianness, T)(T value, Buffer buffer) {
	serializeImpl!(endianness, L, lengthEndianness, T)(buffer, value);
	return buffer.data!ubyte;
}

/// ditto
ubyte[] serialize(Endian endianness, L, Endian lengthEndianness, T)(T value) {
	Buffer buffer = xalloc!Buffer(64);
	scope(exit) xfree(buffer);
	return serialize!(endianness, L, lengthEndianness, T)(value, buffer).dup;
}

/// ditto
ubyte[] serialize(Endian endianness, L, T)(T value, Buffer buffer) {
	return serialize!(endianness, L, endianness, T)(value, buffer);
}

/// ditto
ubyte[] serialize(Endian endianness, L, T)(T value) {
	return serialize!(endianness, L, endianness, T)(value);
}

/// ditto
ubyte[] serialize(Endian endianness, T)(T value, Buffer buffer) {
	return serialize!(endianness, size_t)(value, buffer);
}

/// ditto
ubyte[] serialize(Endian endianness, T)(T value) {
	return serialize!(endianness, size_t)(value);
}

/// ditto
ubyte[] serialize(T)(T value, Buffer buffer) {
	return serialize!(endian, size_t, T)(value, buffer);
}

/// ditto
ubyte[] serialize(T)(T value) {
	return serialize!(endian, size_t, T)(value);
}

/**
 * Deserializes some data.
 */
T deserialize(T, Endian endianness, L, Endian lengthEndianness)(Buffer buffer) {
	return deserializeImpl!(endianness, L, lengthEndianness, T)(buffer);
}

/// ditto
T deserialize(T, Endian endianness, L, Endian lengthEndianness)(in ubyte[] data) {
	Buffer buffer = xalloc!Buffer(data);
	scope(exit) xfree(buffer);
	return deserialize!(T, endianness, L, lengthEndianness)(buffer);
}

/// ditto
T deserialize(T, Endian endianness, L)(Buffer buffer) {
	return deserialize!(T, endianness, L, endianness)(buffer);
}

/// ditto
T deserialize(T, Endian endianness, L)(in ubyte[] data) {
	return deserialize!(T, endianness, L, endianness)(data);
}

/// ditto
T deserialize(T, Endian endianness)(Buffer buffer) {
	return deserialize!(T, endianness, size_t)(buffer);
}

/// ditto
T deserialize(T, Endian endianness)(in ubyte[] data) {
	return deserialize!(T, endianness, size_t)(data);
}

/// ditto
T deserialize(T)(Buffer buffer) {
	return deserialize!(T, endian, size_t)(buffer);
}

/// ditto
T deserialize(T)(in ubyte[] data) {
	return deserialize!(T, endian, size_t)(data);
}

// -----------
// common data
// -----------

enum EndianType {
	
	bigEndian = cast(int)Endian.bigEndian,
	littleEndian = cast(int)Endian.littleEndian,
	var,
	
}

template Members(T, alias Only) {
	
	import std.typetuple : TypeTuple;
	
	mixin({
			
		string ret = "alias Members = TypeTuple!(";
		foreach(member ; __traits(derivedMembers, T)) {
			static if(is(typeof(mixin("T." ~ member)))) {
				mixin("alias M = typeof(T." ~ member ~ ");");
				static if(
					isType!M &&
					!isCallable!M &&
					!__traits(compiles, { mixin("auto test=T." ~ member ~ ";"); }) &&			// static members
					!__traits(compiles, { mixin("auto test=T.init." ~ member ~ "();"); }) &&	// properties
					!hasUDA!(__traits(getMember, T, member), Exclude) &&
					!hasUDA!(__traits(getMember, T, member), Only)
					) {
					ret ~= `"` ~ member ~ `",`;
					
				}
			}
		}
		return ret ~ ");";
		
	}());
	
}

// -------------
// serialization
// -------------

void serializeImpl(Endian endianness, L, Endian lengthEndianness, T)(Buffer buffer, T value) {
	static if(isVar!L) serializeImpl!(cast(EndianType)endianness, L.Type, EndianType.var, L.Type, EndianType.var, T)(buffer, value);
	else serializeImpl!(cast(EndianType)endianness, L, cast(EndianType)lengthEndianness, L, cast(EndianType)lengthEndianness, T)(buffer, value);
}

void serializeImpl(EndianType endianness, OL, EndianType ole, CL, EndianType cle, T)(Buffer buffer, T value) {
	static if(isArray!T) {
		static if(isDynamicArray!T) serializeLength!(cle, CL)(buffer, value.length);
		serializeArray!(endianness, OL, ole)(buffer, value);
	} else static if(isAssociativeArray!T) {
		serializeLength!(cle, CL)(buffer, value.length);
		serializeAssociativeArray!(endianness, OL, ole)(buffer, value);
	} else static if(isTuple!T) {
		serializeTuple!(endianness, OL, ole)(buffer, value);
	} else static if(is(T == class) || is(T == struct)) {
		serializeMembers!(endianness, OL, ole)(buffer, value);
	} else static if(is(T : bool) || isIntegral!T || isFloatingPoint!T || isSomeChar!T) {
		serializeNumber!endianness(buffer, value);
	} else {
		static assert(0, "Cannot serialize " ~ T.stringof);
	}
}

void serializeNumber(EndianType endianness, T)(Buffer buffer, T value) {
	static if(endianness == EndianType.var) {
		static assert(isIntegral!T && T.sizeof > 1, T.stringof ~ " cannot be annotated with @Var");
		buffer.writeVar!T(value);
	} else static if(endianness == EndianType.bigEndian) {
		buffer.write!(Endian.bigEndian, T)(value);
	} else static if(endianness == EndianType.littleEndian) {
		buffer.write!(Endian.littleEndian, T)(value);
	}
}

void serializeLength(EndianType endianness, L)(Buffer buffer, size_t length) {
	static if(L.sizeof < size_t.sizeof) serializeNumber!(endianness, L)(buffer, cast(L)length);
	else serializeNumber!(endianness, L)(buffer, length);
}

void serializeArray(EndianType endianness, OL, EndianType ole, T)(Buffer buffer, T array) if(isArray!T) {
	static if(canSwapEndianness!(ForeachType!T) && !is(ForeachType!T == struct) && !is(ForeachType!T == class) && endianness != EndianType.var) {
		buffer.write!(cast(Endian)endianness)(array);
	} else {
		foreach(value ; array) {
			serializeImpl!(endianness, OL, ole, OL, ole)(buffer, value);
		}
	}
}

void serializeAssociativeArray(EndianType endianness, OL, EndianType ole, T)(Buffer buffer, T array) if(isAssociativeArray!T) {
	foreach(key, value; array) {
		serializeImpl!(endianness, OL, ole, OL, ole)(buffer, key);
		serializeImpl!(endianness, OL, ole, OL, ole)(buffer, value);
	}
}

void serializeTuple(EndianType endianness, OL, EndianType ole, T)(Buffer buffer, T tuple) if(isTuple!T) {
	static foreach(i ; 0..tuple.fieldNames.length) {
		serializeImpl!(endianness, OL, ole, OL, ole)(buffer, tuple[i]);
	}
}

void serializeMembers(EndianType endianness, L, EndianType le, T)(Buffer __buffer, T __container) {
	foreach(member ; Members!(T, DecodeOnly)) {
		
		mixin("alias M = typeof(__container." ~ member ~ ");");
		
		static foreach(uda ; __traits(getAttributes, __traits(getMember, T, member))) {
			static if(is(uda : Custom!C, C)) {
				enum __custom = true;
				uda.C.serialize(mixin("__container." ~ member), __buffer);
			}
		}
		
		static if(!is(typeof(__custom))) mixin({
				
			static if(hasUDA!(__traits(getMember, T, member), LengthImpl)) {
				import std.conv : to;
				auto length = getUDAs!(__traits(getMember, T, member), LengthImpl)[0];
				immutable e = "L, le, " ~ length.type ~ ", " ~ (length.endianness == -1 ? "endianness" : "EndianType." ~ (cast(EndianType)length.endianness).to!string);
			} else {
				immutable e = "L, le, L, le";
			}
			
			static if(hasUDA!(__traits(getMember, T, member), NoLength)) immutable ret = "xserial.serial.serializeArray!(endianness, L, le, M)(__buffer, __container." ~ member ~ ");";
			else static if(hasUDA!(__traits(getMember, T, member), Var)) immutable ret = "xserial.serial.serializeImpl!(EndianType.var, " ~ e ~ ", M)(__buffer, __container." ~ member ~ ");";
			else static if(hasUDA!(__traits(getMember, T, member), BigEndian)) immutable ret = "xserial.serial.serializeImpl!(EndianType.bigEndian, " ~ e ~ ", M)(__buffer, __container." ~ member ~ ");";
			else static if(hasUDA!(__traits(getMember, T, member), LittleEndian)) immutable ret = "xserial.serial.serializeImpl!(EndianType.littleEndian, " ~ e ~ ", M)(__buffer, __container." ~ member ~ ");";
			else immutable ret = "xserial.serial.serializeImpl!(endianness, " ~ e ~ ", M)(__buffer, __container." ~ member ~ ");";

			static if(!hasUDA!(__traits(getMember, T, member), Condition)) return ret;
			else return "with(__container){if(" ~ getUDAs!(__traits(getMember, T, member), Condition)[0].condition ~ "){" ~ ret ~ "}}";
			
		}());
		
	}
}

// ---------------
// deserialization
// ---------------

T deserializeImpl(Endian endianness, L, Endian lengthEndianness, T)(Buffer buffer) {
	static if(isVar!L) return deserializeImpl!(cast(EndianType)endianness, L.Type, EndianType.var, L.Type, EndianType.var, T)(buffer);
	else return deserializeImpl!(cast(EndianType)endianness, L, cast(EndianType)lengthEndianness, L, cast(EndianType)lengthEndianness, T)(buffer);
}

T deserializeImpl(EndianType endianness, OL, EndianType ole, CL, EndianType cle, T)(Buffer buffer) {
	static if(isStaticArray!T) {
		return deserializeStaticArray!(endianness, OL, ole, T)(buffer);
	} else static if(isDynamicArray!T) {
		return deserializeDynamicArray!(endianness, OL, ole, T)(buffer, deserializeLength!(cle, CL)(buffer));
	} else static if(isAssociativeArray!T) {
		return deserializeAssociativeArray!(endianness, OL, ole, T)(buffer, deserializeLength!(cle, CL)(buffer));
	} else static if(isTuple!T) {
		return deserializeTuple!(endianness, OL, ole, T)(buffer);
	} else static if(is(T == class)) {
		T ret = new T();
		deserializeMembers!(endianness, OL, ole)(buffer, ret);
		return ret;
	} else static if(is(T == struct)) {
		T ret;
		deserializeMembers!(endianness, OL, ole)(buffer, &ret);
		return ret;
	} else static if(is(T : bool) || isIntegral!T || isFloatingPoint!T || isSomeChar!T) {
		return deserializeNumber!(endianness, T)(buffer);
	} else {
		static assert(0, "Cannot deserialize " ~ T.stringof);
	}
}

T deserializeNumber(EndianType endianness, T)(Buffer buffer) {
	static if(endianness == EndianType.var) {
		static assert(isIntegral!T && T.sizeof > 1, T.stringof ~ " cannot be annotated with @Var");
		return buffer.readVar!T();
	} else static if(endianness == EndianType.bigEndian) {
		return buffer.read!(Endian.bigEndian, T)();
	} else static if(endianness == EndianType.littleEndian) {
		return buffer.read!(Endian.littleEndian, T)();
	}
}

size_t deserializeLength(EndianType endianness, L)(Buffer buffer) {
	static if(L.sizeof > size_t.sizeof) return cast(size_t)deserializeNumber!(endianness, L)(buffer);
	else return deserializeNumber!(endianness, L)(buffer);
}

T deserializeStaticArray(EndianType endianness, OL, EndianType ole, T)(Buffer buffer) if(isStaticArray!T) {
	T ret;
	foreach(ref value ; ret) {
		value = deserializeImpl!(endianness, OL, ole, OL, ole, ForeachType!T)(buffer);
	}
	return ret;
}

T deserializeDynamicArray(EndianType endianness, OL, EndianType ole, T)(Buffer buffer, size_t length) if(isDynamicArray!T) {
	T ret;
	foreach(i ; 0..length) {
		ret ~= deserializeImpl!(endianness, OL, ole, OL, ole, ForeachType!T)(buffer);
	}
	return ret;
}

T deserializeAssociativeArray(EndianType endianness, OL, EndianType ole, T)(Buffer buffer, size_t length) if(isAssociativeArray!T) {
	T ret;
	foreach(i ; 0..length) {
		ret[deserializeImpl!(endianness, OL, ole, OL, ole, KeyType!T)(buffer)] = deserializeImpl!(endianness, OL, ole, OL, ole, ValueType!T)(buffer);
	}
	return ret;
}

T deserializeNoLengthArray(EndianType endianness, OL, EndianType ole, T)(Buffer buffer) if(isDynamicArray!T) {
	T ret;
	try {
		while(true) ret ~= deserializeImpl!(endianness, OL, ole, OL, ole, ForeachType!T)(buffer);
	} catch(BufferOverflowException) {}
	return ret;
}

T deserializeTuple(EndianType endianness, OL, EndianType ole, T)(Buffer buffer) if(isTuple!T) {
	T ret;
	foreach(i, U; T.Types) {
		ret[i] = deserializeImpl!(endianness, OL, ole, OL, ole, U)(buffer);
	}
	return ret;
}

void deserializeMembers(EndianType endianness, L, EndianType le, C)(Buffer __buffer, C __container) {
	static if(isPointer!C) alias T = typeof(*__container);
	else alias T = C;
	foreach(member ; Members!(T, EncodeOnly)) {
		
		mixin("alias M = typeof(__container." ~ member ~ ");");
		
		static foreach(uda ; __traits(getAttributes, __traits(getMember, T, member))) {
			static if(is(uda : Custom!C, C)) {
				enum __custom = true;
				mixin("__container." ~ member) = uda.C.deserialize(__buffer);
			}
		}
		
		static if(!is(typeof(__custom))) mixin({
				
				static if(hasUDA!(__traits(getMember, T, member), LengthImpl)) {
					import std.conv : to;
					auto length = getUDAs!(__traits(getMember, T, member), LengthImpl)[0];
					immutable e = "L, le, " ~ length.type ~ ", " ~ (length.endianness == -1 ? "endianness" : "EndianType." ~ (cast(EndianType)length.endianness).to!string);
				} else {
					immutable e = "L, le, L, le";
				}
				
				static if(hasUDA!(__traits(getMember, T, member), NoLength)) immutable ret = "__container." ~ member ~ "=xserial.serial.deserializeNoLengthArray!(endianness, L, le, M)(__buffer);";
				else static if(hasUDA!(__traits(getMember, T, member), Var)) immutable ret = "__container." ~ member ~ "=xserial.serial.deserializeImpl!(EndianType.var, " ~ e ~ ", M)(__buffer);";
				else static if(hasUDA!(__traits(getMember, T, member), BigEndian)) immutable ret = "__container." ~ member ~ "=xserial.serial.deserializeImpl!(EndianType.bigEndian, " ~ e ~ ", M)(__buffer);";
				else static if(hasUDA!(__traits(getMember, T, member), LittleEndian)) immutable ret = "__container." ~ member ~ "=xserial.serial.deserializeImpl!(EndianType.littleEndian, " ~ e ~ ", M)(__buffer);";
				else immutable ret = "__container." ~ member ~ "=xserial.serial.deserializeImpl!(endianness, " ~ e ~ ", M)(__buffer);";
				
				static if(!hasUDA!(__traits(getMember, T, member), Condition)) return ret;
				else return "with(__container){if(" ~ getUDAs!(__traits(getMember, T, member), Condition)[0].condition ~ "){" ~ ret ~ "}}";
				
			}());
		
	}
}

// ---------
// unittests
// ---------

@("numbers") unittest {

	// bools and numbers
	
	assert(true.serialize() == [1]);
	assert(5.serialize!(Endian.bigEndian)() == [0, 0, 0, 5]);
	
	assert(deserialize!(int, Endian.bigEndian)([0, 0, 0, 5]) == 5);

	version(LittleEndian) assert(12.serialize() == [12, 0, 0, 0]);
	version(BigEndian) assert(12.serialize() == [0, 0, 0, 12]);

}

@("arrays") unittest {

	assert([1, 2, 3].serialize!(Endian.bigEndian, uint)() == [0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3]);
	assert([1, 2, 3].serialize().deserialize!(int[])() == [1, 2, 3]);

	ushort[2] test1 = [1, 2];
	assert(test1.serialize!(Endian.bigEndian)() == [0, 1, 0, 2]);
	test1 = deserialize!(ushort[2], Endian.littleEndian)([2, 0, 1, 0]);
	assert(test1 == [2, 1]);

}

@("associative arrays") unittest {

	// associative arrays

	int[ushort] test;
	test[1] = 112;
	assert(test.serialize!(Endian.bigEndian, uint)() == [0, 0, 0, 1, 0, 1, 0, 0, 0, 112]);

	test = deserialize!(int[ushort], Endian.bigEndian, ubyte)([1, 0, 0, 0, 0, 0, 55]);
	assert(test == [ushort(0): 55]);

}

@("tuples") unittest {

	import std.typecons : Tuple, tuple;

	assert(tuple(1, "test").serialize!(Endian.bigEndian, ushort)() == [0, 0, 0, 1, 0, 4, 't', 'e', 's', 't']);

	Tuple!(ubyte, "a", uint[], "b") test;
	test.a = 12;
	assert(test.serialize!(Endian.littleEndian, uint)() == [12, 0, 0, 0, 0]);
	assert(deserialize!(typeof(test), Endian.bigEndian, ushort)([12, 0, 0]) == test);

}

@("structs and classes") unittest {

	struct Test {

		byte a, b, c;

	}

	Test test = Test(1, 3, 55);
	assert(test.serialize() == [1, 3, 55]);

	assert(deserialize!Test([1, 3, 55]) == test);

}

@("attributes") unittest {

	struct Test1 {

		@BigEndian int a;

		@EncodeOnly @LittleEndian ushort b;

		@Condition("a==1") @Var uint c;

		@DecodeOnly @Var uint d;

		@Exclude ubyte e;

	}

	Test1 test1 = Test1(1, 2, 3, 4, 5);
	assert(test1.serialize() == [0, 0, 0, 1, 2, 0, 3]);
	assert(deserialize!Test1([0, 0, 0, 1, 4, 12]) == Test1(1, 0, 4, 12));

	test1.a = 0;
	assert(test1.serialize() == [0, 0, 0, 0, 2, 0]);
	assert(deserialize!Test1([0, 0, 0, 0, 0, 0, 0, 0]) == Test1(0, 0, 0, 0));

	struct Test2 {

		ubyte[] a;

		@Length!ushort ushort[] b;

		@NoLength uint[] c;

	}

	Test2 test2 = Test2([1, 2], [3, 4], [5, 6]);
	assert(test2.serialize!(Endian.bigEndian, uint)() == [0, 0, 0, 2, 1, 2, 0, 2, 0, 3, 0, 4, 0, 0, 0, 5, 0, 0, 0, 6]);
	assert(deserialize!(Test2, Endian.bigEndian, uint)([0, 0, 0, 2, 1, 2, 0, 2, 0, 3, 0, 4, 0, 0, 0, 5, 0, 0, 0, 6, 1]) == test2);

	struct Test3 {

		@EndianLength!ushort(Endian.littleEndian) @LittleEndian ushort[] a;

		@NoLength ushort[] b;

	}

	Test3 test3 = Test3([1, 2], [3, 4]);
	assert(test3.serialize!(Endian.bigEndian)() == [2, 0, 1, 0, 2, 0, 0, 3, 0, 4]);

	struct Test4 {

		ubyte a;

		@LittleEndian uint b;

	}

	struct Test5 {

		@Length!ubyte Test4[] a;

		@NoLength Test4[] b;

	}

	Test5 test5 = Test5([Test4(1, 2)], [Test4(1, 2), Test4(3, 4)]);
	assert(test5.serialize() == [1, 1, 2, 0, 0, 0, 1, 2, 0, 0, 0, 3, 4, 0, 0, 0]);
	assert(deserialize!Test5([1, 1, 2, 0, 0, 0, 1, 2, 0, 0, 0, 3, 4, 0, 0, 0]) == test5);

}

@("using buffer") unittest {

	Buffer buffer = new Buffer(64);

	serialize(ubyte(55), buffer);
	assert(buffer.data.length == 1);
	assert(buffer.data!ubyte == [55]);

	assert(deserialize!ubyte(buffer) == 55);
	assert(buffer.data.length == 0);

}
