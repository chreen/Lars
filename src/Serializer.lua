local Definitions = require(script.Parent:WaitForChild("Definitions"))
local Stream = require(script.Parent:WaitForChild("Stream"))

local Serializer = {}
Serializer.__index = Serializer

export type Serializer = {
  _stream: Stream.Stream,
  _chunk: Definitions.Chunk,
  _patternCache: { [string]: string },

  writeInt: (Serializer, number) -> (),
  writeInstructions: (Serializer, { Definitions.Instruction }) -> (),
  writeConstants: (Serializer, { Definitions.Constant }) -> (),
  writePrototype: (Serializer, Definitions.Prototype) -> (),
  writeLocals: (Serializer, { Definitions.Local }) -> (),
  serialize: (Serializer) -> (string, Stream.Stream),
} & typeof(setmetatable({}, {}))

--- Write an integer with size from the chunk's signature to the stream
---@param int number Integer to write
function Serializer:writeInt(int: number)
  self._stream:writePattern(self._patternCache["int"], int)
end

--- Write an array of Lua instructions to the stream
---@param code array Array of instructions to write
function Serializer:writeInstructions(code: { Definitions.Instruction })
  self:writeInt(#code)

  for _, inst in ipairs(code) do
    -- TODO: update raw value in mapper
    self._stream:writePattern("I4", inst.raw)
  end
end

--- Write an array of Lua constants to the stream
---@param consts array Array of constants to write
function Serializer:writeConstants(consts: { Definitions.Constant })
  self:writeInt(#consts)

  for _, const in ipairs(consts) do
    self._stream:writePattern("B", Definitions.constantTypeLookup[const.type])

    if const.type == "LUA_TBOOLEAN" then
      self._stream:writePattern("B", if const.value then 1 else 0)
    elseif const.type == "LUA_TNUMBER" then
      self._stream:writePattern(self._patternCache["number"], const.value)
    elseif const.type == "LUA_TSTRING" then
      self._stream:writePattern(self._patternCache["string"], const.value .. "\0")
    end
  end
end

--- Write a Lua prototype to the stream
---@param proto Definitions.Prototype Prototype to write
function Serializer:writePrototype(proto: Definitions.Prototype)
  -- write basic proto data
  self._stream:writePattern(
    self._patternCache["prototype"],
    (if #proto.source > 0 then proto.source .. "\0" else proto.source),
    proto.firstLine,
    proto.lastLine,
    proto.numUpvals,
    proto.numParams,
    proto.isVararg,
    proto.stackSize
  )

  -- write instructions, constants
  self:writeInstructions(proto.code)
  self:writeConstants(proto.consts)

  -- write child prototypes
  self:writeInt(#proto.protos)
  for _, sub in ipairs(proto.protos) do
    self:writePrototype(sub)
  end

  -- write line info
  local sizeLines = #proto.lines
  self:writeInt(sizeLines)
  local linePattern = string.rep(self._patternCache["int"], sizeLines)
  self._stream:writePattern(linePattern, table.unpack(proto.lines))

  -- write local variable info
  self:writeLocals(proto.locals)

  -- write upvalue names
  self:writeInt(#proto.upvalues)
  for _, upval in ipairs(proto.upvalues) do
    self._stream:writePattern(self._patternCache["string"], upval .. "\0")
  end
end

--- Write an array of Lua local variables to the stream
---@param locals array Array of local variables to write
function Serializer:writeLocals(locals: { Definitions.Local })
  self:writeInt(#locals)

  for _, var in ipairs(locals) do
    self._stream:writePattern(self._patternCache["local"], var.name .. "\0", var.startPc, var.endPc)
  end
end

--- Serialize the chunk into Lua bytecode defined by the signature
---@return string bytecode Resulting Lua bytecode, as a string
---@return Stream.Stream bytecodeStream Resulting Lua bytecode, as a stream
function Serializer:serialize(): (string, Stream.Stream)
  local sig = self._chunk.signature

  -- first, write the signature
  self._stream:writePattern(
    "c4BBBBBBBB",
    sig.header,
    sig.version,
    if sig.official then 0 else 1,
    if sig.endian then 1 else 0,
    sig.int,
    sig.size_t,
    4,
    sig.lua_Number,
    0
  )

  -- then the top-level prototype
  self:writePrototype(self._chunk.head)

  self._stream:seek(0, "begin")
  return self._stream:toString(), self._stream
end

--- Creates a new serializer with the given chunk.
--- Verifies a few parameters to ensure compatibility.
--- (instruction & number size, integral flag)
---@param chunk Definitions.Chunk Chunk to serialize
---@return Serializer serializer Resulting serializer
function Serializer.new(chunk: Definitions.Chunk): Serializer
  local stream = Stream.new()

  -- a few unsupported parameters
  assert(chunk.signature.instruction == 4, "Invalid instruction size, expected 4")
  assert(
    chunk.signature.lua_Number == 4 or chunk.signature.lua_Number == 8,
    "Invalid number size, expected float or double"
  )
  assert(chunk.signature.integral == false, "Integral flag unsupported")

  -- set stream's endianness
  stream.endian = if chunk.signature.endian then "<" else ">"

  -- cache certain patterns
  local patternCache = {}
  patternCache["int"] = "I" .. chunk.signature.int
  patternCache["string"] = "s" .. chunk.signature.size_t
  patternCache["number"] = if chunk.signature.lua_Number == 4 then "f" else "d"
  patternCache["prototype"] = patternCache["string"] -- source name
    .. patternCache["int"] -- first line defined
    .. patternCache["int"] -- last line defined
    .. "BBBB" -- upvalue count, param count, vararg flag, stack size
  patternCache["local"] = patternCache["string"] -- variable name
    .. patternCache["int"] -- start PC
    .. patternCache["int"] -- end PC

  local self = {
    _stream = stream,
    _chunk = chunk,
    _patternCache = patternCache,
  }

  return setmetatable(self :: any, Serializer) :: Serializer
end

return Serializer
