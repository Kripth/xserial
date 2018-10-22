module xserial.attribute;

import std.system : Endian;
import std.traits : isIntegral;

import xbuffer.varint : isVar;

import xserial.serial : EndianType;

/**
 * Excludes the field from both encoding and decoding.
 */
enum Exclude;

/**
 * Includes this even if it would otherwise be excluded.
 * If Exclude (or other UDA(@)) and Include are present value will be included.
 * Can also be used on @property methods to include them. (Be sure both the setter and getter exist!)
 * If used on a value of a base class value will be included.
 */
 enum Include;

/**
 * Excludes the field from decoding, encode only.
 */
enum EncodeOnly;

/**
 * Excludes the field from encoding, decode only.
 */
enum DecodeOnly;

/**
 * Only encode/decode the field when the condition is met.
 * The condition is placed inside an if statement and can access
 * the variables and functions of the class/struct (without `this`).
 * 
 * This attribute can be used with EncodeOnly and DecodeOnly.
 */
struct Condition { string condition; }

/**
 * Indicates the endianness for the type and its subtypes.
 */
enum BigEndian;

/// ditto
enum LittleEndian;

/**
 * Encodes and decodes as a Google varint.
 */
enum Var;

/**
 * Indicates that the array has no length. It should only be used
 * as last field in the class/struct.
 */
enum NoLength;

struct LengthImpl { string type; int endianness; }

template Length(T) if(isIntegral!T) { enum Length = LengthImpl(T.stringof, -1); }

template Length(T) if(isVar!T) { enum Length = LengthImpl(T.Base.stringof, EndianType.var); }

LengthImpl EndianLength(T)(Endian endianness) if(isIntegral!T) { return LengthImpl(T.stringof, endianness); }

struct Custom(T) if(is(T == struct) || is(T == class) || is(T == interface)) { alias C = T; }

unittest { // for code coverage

	EndianLength!uint(Endian.bigEndian);

}
