module xserial;

public import xbuffer;

public import xserial.attribute : Exclude, Include, EncodeOnly, DecodeOnly, Condition, BigEndian, LittleEndian, Var, NoLength, Length, Custom;
public import xserial.serial : serialize, deserialize;
