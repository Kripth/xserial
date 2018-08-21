module xserial.serial;

import std.system : Endian, endian;
import std.traits : isArray, isDynamicArray, isAssociativeArray, ForeachType, isIntegral, isFloatingPoint, isSomeChar, isType, isCallable, hasUDA;

import xbuffer : Buffer;
import xbuffer.varint : isVar;

import xserial.attribute;

/**
 * Serializes some data.
 */
ubyte[] serialize(Endian endianness, L, T)(T value, Buffer buffer) {
	serializeImpl!(endianness, L, T)(buffer, value);
	return buffer.data!ubyte;
}

/// ditto
ubyte[] serialize(Endian endianness, L, T)(T value) {
	return serialize!(endianness, L, T)(value, new Buffer(64));
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
T deserialize(T, Endian endianness, L)(Buffer buffer) {
	return T.init;
}

/// ditto
T deserialize(T, Endian endianness, L)(in void[] buffer) {
	return deserialize!(T, endianness, L)(new Buffer(buffer));
}

/// ditto
T deserialize(T, Endian endianness)(Buffer buffer) {
	return deserialize!(T, endianness, size_t)(buffer);
}

/// ditto
T deserialize(T, Endian endianness)(in void[] buffer) {
	return deserialize!(T, endianness, size_t)(buffer);
}

/// ditto
T deserialize(T)(Buffer buffer) {
	return deserialize!(T, endian, size_t)(buffer);
}

/// ditto
T deserialize(T)(in void[] buffer) {
	return deserialize!(T, endian, size_t)(buffer);
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

private void serializeImpl(Endian endianness, L, T)(Buffer buffer, T value) {
	static if(isVar!L) serializeImpl!(cast(EndianType)endianness, L.Type, EndianType.var, L.Type, EndianType.var, T)(buffer, value);
	else serializeImpl!(cast(EndianType)endianness, L, cast(EndianType)endianness, L, cast(EndianType)endianness, T)(buffer, value);
}

private void serializeImpl(EndianType endianness, OL, EndianType ole, CL, EndianType cle, T)(Buffer buffer, T value) {
	static if(isArray!T) {
		static if(isDynamicArray!T) serializeLength!(cle, CL)(buffer, value.length);
		serializeArray!(endianness, OL, ole)(buffer, value);
	} else static if(isAssociativeArray!T) {
		serializeLength!(cle, CL)(buffer, value.length);
		serializeAssociativeArray!(endianness, OL, ole)(buffer, value);
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
	static if(L.sizeof < size_t.sizeof) serializeImpl!(endianness, L)(buffer, cast(L)length);
	else serializeNumber!(endianness, L)(buffer, length);
}

void serializeArray(EndianType endianness, OL, EndianType ole, T)(Buffer buffer, T array) if(isArray!T) {
	//TODO xbuffer supports writing arrays that canSwapEndianness
	foreach(value ; array) {
		serializeImpl!(endianness, OL, ole, OL, ole)(buffer, value);
	}
}

void serializeAssociativeArray(EndianType endianness, OL, EndianType ole, T)(Buffer buffer, T array) if(isAssociativeArray!T) {
	foreach(key, value; array) {
		serializeImpl!(endianness, OL, ole, OL, ole)(buffer, key);
		serializeImpl!(endianness, OL, ole, OL, ole)(buffer, value);
	}
}

void serializeMembers(EndianType endianness, L, EndianType le, T)(Buffer __buffer, T __container) {
	foreach(member ; Members!(T, DecodeOnly)) {
		
		mixin("alias M = typeof(__container." ~ member ~ ");");
		
		static foreach(uda ; __traits(getAttributes, __traits(getMember, T, member))) {
			static if(is(uda : Custom!C, C)) {
				enum __custom = true;
				uda.C.encode(mixin("__container." ~ member), __buffer);
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
				
				static if(hasUDA!(__traits(getMember, T, member), Bytes)) immutable ret = "__buffer.write(__container." ~ member ~ ");";
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

// ---------
// unittests
// ---------

@("numbers") unittest {

	// bools and numbers
	
	assert(true.serialize() == [1]);
	assert(5.serialize!(Endian.bigEndian)() == [0, 0, 0, 5]);
	
	//assert([0, 0, 0, 5].deserialize!(int, Endian.bigEndian)() == 5);

	version(LittleEndian) assert(12.serialize() == [12, 0, 0, 0]);
	version(BigEndian) assert(12.serialize() == [0, 0, 0, 12]);

}

@("arrays") unittest {

	assert([1, 2, 3].serialize!(Endian.bigEndian, uint)() == [0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3]);

	ushort[2] test = [1, 2];
	assert(test.serialize!(Endian.bigEndian)() == [0, 1, 0, 2]);
	//test = deserialize!(Endian.littleEndian)([2, 0, 1, 0]);
	//assert(test == [2, 1]);

}

@("associative arrays") unittest {

	// associative arrays

	uint[ushort] test;
	test[1] = 112;
	assert(test.serialize!(Endian.bigEndian, uint)() == [0, 0, 0, 1, 0, 1, 0, 0, 0, 112]);

}

@("structs and classes") unittest {

	struct Test {

		byte a, b, c;

	}

	Test test = Test(1, 3, 55);
	assert(test.serialize() == [1, 3, 55]);

}

@("attributes") unittest {

	struct Test {

		@BigEndian int a;

		@LittleEndian ushort b;

		@Var uint c;

	}

	Test test = Test(1, 2, 3);
	assert(test.serialize() == [0, 0, 0, 1, 2, 0, 3]);

}
