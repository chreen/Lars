--!strict

export type Stream = {
  source: string,
  index: number,
  endian: string,

  readPattern: (Stream, string) -> ...any,
  writePattern: (Stream, string, ...any) -> number,
  toString: (Stream) -> string,
  seek: (Stream, number, SeekOrigin?) -> number,
}

export type SeekOrigin = "begin" | "current" | "end"

local Stream = {}

function Stream.new(source: string?): Stream
  local new = {
    source = source or "",
    index = 1,
    endian = "<",
  } :: Stream

  --- Read a `string.unpack` format and return the values.
  ---@param pattern string Format string to use
  ---@return any values Values read from stream
  function new:readPattern(pattern: string): ...any
    local ret = table.pack(string.unpack(self.endian .. pattern, self.source, self.index))
    self.index = ret[ret.n]

    return table.unpack(ret, 1, ret.n - 1)
  end

  --- Write a `string.pack` format with the given values to the stream.
  --- Will overwrite existing data!
  ---@param pattern string Pattern string to write, followed by values
  ---@return number newIndex New index of stream (source length)
  function new:writePattern(pattern: string, ...: any): number
    local packed = string.pack(self.endian .. pattern, ...)
    local size = #packed

    self.source = string.sub(self.source, 1, self.index - 1) .. packed .. string.sub(self.source, self.index + size, -1)
    self.index += size

    return self.index
  end

  --- Returns the source string of this Stream.
  ---@return string source
  function new:toString(): string
    return self.source
  end

  --- Set the current stream's position
  ---@param offset number Offset to add
  ---@param origin SeekOrigin? Defaults to "current"
  ---@return number newIndex New index of stream
  function new:seek(offset: number, origin: SeekOrigin?): number
    local newIdx = (if origin == "begin" then 1 elseif origin == "end" then #self.source else self.index) + offset
    self.index = math.clamp(newIdx, 1, #self.source)

    return self.index
  end

  return new
end

return Stream
