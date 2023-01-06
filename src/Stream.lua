--!strict

export type Stream = {
  source: string,
  index: number,
  endian: string,

  readPattern: (Stream, string) -> ...any,
}

local Stream = {}

function Stream.new(source: string): Stream
  local new = {
    source = source,
    index = 1,
    endian = "<",
  } :: Stream

  function new:readPattern(pattern: string): ...any
    local ret = table.pack(string.unpack(self.endian .. pattern, self.source, self.index))
    self.index = ret[ret.n]

    return table.unpack(ret, 1, ret.n - 1)
  end

  return new
end

return Stream
