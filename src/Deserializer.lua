--!strict

local Definitions = require(script.Parent:WaitForChild("Definitions"))
local Stream = require(script.Parent:WaitForChild("Stream"))

local Deserializer = {}
Deserializer.__index = Deserializer

export type Deserializer = {
  _stream: Stream.Stream,
  _signature: Definitions.Signature,
  _patternCache: { [string]: string },

  readInt: (Deserializer) -> number,
  readString: (Deserializer) -> string,
  readInstruction: (Deserializer) -> Definitions.Instruction,
  readConstant: (Deserializer) -> Definitions.Constant,
  readPrototype: (Deserializer) -> Definitions.Prototype,
  deserialize: (Deserializer) -> Definitions.Chunk,
} & typeof(setmetatable({}, {}))

--- Read an integer with the size from the signature
---@return number int Resulting integer
function Deserializer:readInt(): number
  return self._stream:readPattern(self._patternCache["int"])
end

--- Read a string with the size_t size from the signature
---@return string string Resulting string
function Deserializer:readString(): string
  return string.sub(self._stream:readPattern(self._patternCache["string"]), 1, -2)
end

--- Read an unsigned 32-bit instruction, then extract every possible field
---@return Definitions.Instruction instruction Resulting Lua instruction
function Deserializer:readInstruction(): Definitions.Instruction
  local raw = self._stream:readUInt32()

  local ins = {
    raw = raw,
    op = bit32.extract(raw, 0, 6),
    A = bit32.extract(raw, 6, 8),
    C = bit32.extract(raw, 14, 9),
    B = bit32.extract(raw, 23, 9),
    Bx = bit32.extract(raw, 14, 18),
    sBx = bit32.extract(raw, 14, 18) - 131071,

    kB = nil,
    kC = nil,
  }

  ins.isRkB = Definitions.bOpArgK[ins.op] and ins.B > 0xFF or false
  ins.isRkC = Definitions.cOpArgK[ins.op] and ins.C > 0xFF or false

  return ins
end

--- Read a Lua constant from the stream
---@return Definitions.Constant constant Resulting Lua constant
function Deserializer:readConstant(): Definitions.Constant
  local typeByte = self._stream:readByte()
  local cons: Definitions.Constant = {
    type = assert(Definitions.constantTypes[typeByte], "Invalid constant type " .. typeByte),
  }

  if typeByte == 1 then -- LUA_TBOOLEAN
    cons.value = self._stream:readByte() ~= 0
  elseif typeByte == 3 then -- LUA_TNUMBER
    cons.value = self._stream:readPattern(self._patternCache["number"])
  elseif typeByte == 4 then -- LUA_TSTRING
    cons.value = self:readString()
  else -- LUA_TNIL
    cons.value = nil
  end

  return cons
end

--- Read a Lua prototype and its children
---@return Definitions.Prototype proto Resulting prototype
function Deserializer:readPrototype(): Definitions.Prototype
  local source = self:readString() :: string -- good job luau

  if #source == 0 then
    source = "@Lars"
  end

  local firstLine, lastLine = self:readInt(), self:readInt()

  local numUpvals, numParams, varargFlag, stackSize = self._stream:readPattern("BBBB")

  -- read instructions
  local sizeCode = self:readInt()
  local code = table.create(sizeCode)
  for _ = 1, sizeCode do
    table.insert(code, self:readInstruction())
  end

  -- read constants
  local sizeK = self:readInt()
  local consts = table.create(sizeK)
  for _ = 1, sizeK do
    table.insert(consts, self:readConstant())
  end

  -- preload constants to instructions
  for _, inst: Definitions.Instruction in ipairs(code) do
    if Definitions.bxOpArgK[inst.op] then
      inst.kB = consts[inst.Bx + 1].value
      continue -- iABx, skip other fields
    end

    if inst.isRkB then
      inst.kB = consts[inst.B - 0xFF].value
    end

    if inst.isRkC then
      inst.kC = consts[inst.C - 0xFF].value
    end
  end

  -- read child prototypes
  local sizeP = self:readInt()
  local protos = table.create(sizeP)
  for _ = 1, sizeP do
    table.insert(protos, self:readPrototype())
  end

  -- read line numbers
  local sizeLines = self:readInt()
  local lines = table.create(sizeLines)
  for _ = 1, sizeLines do
    table.insert(lines, self:readInt())
  end

  -- read local variables
  local sizeLocals = self:readInt()
  local locals = table.create(sizeLocals)
  for _ = 1, sizeLocals do
    table.insert(locals, self:readLocal())
  end

  -- read upvalue names
  local sizeUpvalues = self:readInt()
  local upvalues = table.create(sizeUpvalues)
  for _ = 1, sizeUpvalues do
    table.insert(upvalues, self:readString())
  end

  -- package final prototype
  return {
    source = source,
    firstLine = firstLine,
    lastLine = lastLine,
    numUpvals = numUpvals,
    numParams = numParams,
    isVararg = varargFlag,
    stackSize = stackSize,
    code = code,
    consts = consts,
    protos = protos,
    lines = lines,
    locals = locals,
    upvalues = upvalues,
  }
end

--- Read a Lua local variable
---@return Definitions.Local local Resulting local variable
function Deserializer:readLocal(): Definitions.Local
  return {
    name = self:readString(),
    startPc = self:readInt(),
    endPc = self:readInt(),
  }
end

--- Deserialize bytecode into a Chunk
---@return Definitions.Chunk chunk Resulting chunk
function Deserializer:deserialize(): Definitions.Chunk
  return {
    signature = self._signature,
    head = self:readPrototype(),
  }
end

--- Creates a new deserializer with the given bytecode string.
--- Will verify bytecode signature and error if incompatible.
---@param bytecode string Bytecode string
---@return Deserializer deserializer Resulting deserializer
function Deserializer.new(bytecode: string): Deserializer
  local stream = Stream.new(bytecode)

  local header, version, format, endian, sizeInt, sizeSizeT, sizeInstruction, sizeNumber, integral =
    stream:readPattern("c4BBBBBBBB") -- 4 byte string, then 8 individual bytes

  -- validate signature data
  assert(header == "\x1BLua", "Invalid bytecode header, expected \\x1BLua")
  assert(version == 0x51, "Invalid bytecode version, expected 0x51")
  assert(format == 0, "Invalid bytecode format (not official)")
  assert(sizeInstruction == 4, "Invalid instruction size, expected 4")
  assert(sizeNumber == 4 or sizeNumber == 8, "Invalid number size, expected float or double")
  assert(integral == 0, "Integral flag unsupported")

  local signature: Definitions.Signature = {
    header = header,
    version = version,
    official = format == 0,
    endian = endian == 1,
    int = sizeInt,
    size_t = sizeSizeT,
    instruction = sizeInstruction,
    lua_Number = sizeNumber,
    integral = integral ~= 1,
  }

  -- set stream's endianness
  stream.littleEndian = signature.endian

  -- cache certain patterns
  local patternCache = {}
  patternCache["int"] = "I" .. sizeInt
  patternCache["string"] = "s" .. sizeSizeT
  patternCache["number"] = if sizeNumber == 4 then "f" else "d"

  local self = {
    _stream = stream,
    _signature = signature,
    _patternCache = patternCache,
  }

  return setmetatable(self :: any, Deserializer) :: Deserializer
end

return Deserializer
