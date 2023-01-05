export type Stream = {
  source: string,
  index: number,
  littleEndian: boolean,

  getEndianPattern: (Stream) -> string,
  readPattern: (Stream, string) -> ...any,
  readByte: (Stream) -> number,
  readUInt32: (Stream) -> number,
  readInt32: (Stream) -> number,
  readUInt64: (Stream) -> number,
  readInt64: (Stream) -> number,
  readFloat: (Stream) -> number,
  readDouble: (Stream) -> number,
  readLString: (Stream, number) -> string,
  readString: (Stream, number) -> string,
} & typeof(setmetatable({}, {}))

local Stream = {}
Stream.__index = Stream

function Stream:getEndianPattern(): string
  return if self.littleEndian then "<" else ">"
end

function Stream:readPattern(pattern: string): ...any
  local ret = table.pack(string.unpack(self:getEndianPattern() .. pattern, self.source, self.index))
  self.index = table.remove(ret, ret.n)

  return table.unpack(ret)
end

function Stream:readByte(): number
  return self:readPattern("B") :: number
end

function Stream:readUInt32(): number
  return self:readPattern("I4") :: number
end

function Stream:readInt32(): number
  return self:readPattern("i4") :: number
end

function Stream:readUInt64(): number
  return self:readPattern("L") :: number
end

function Stream:readInt64(): number
  return self:readPattern("l") :: number
end

function Stream:readFloat(): number
  return self:readPattern("f") :: number
end

function Stream:readDouble(): number
  return self:readPattern("d") :: number
end

function Stream:readLString(sizeLen: number)
  return self:readPattern("s" .. sizeLen) :: string
end

function Stream:readString(len: number): string
  return self:readPattern("c" .. len) :: string
end

function Stream.new(source: string): Stream
  local self = {
    source = source,
    index = 1,
    littleEndian = true,
  }

  return setmetatable(self :: any, Stream) :: Stream
end

return Stream
