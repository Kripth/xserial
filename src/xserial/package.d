module xserial;

public import xbuffer;

public import xserial.attribute : Exclude, EncodeOnly, DecodeOnly, Condition, BigEndian, LittleEndian, Var, Bytes, Length, Custom;
public import xserial.serial : serialize, deserialize;
