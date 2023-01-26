-- no strict mode, string.unpack causes issues with proto return

local Definitions = require(script.Parent:WaitForChild("Definitions"))
local Stream = require(script.Parent:WaitForChild("Stream"))

local Deserializer = {}
Deserializer.__index = Deserializer

export type Deserializer = {
  _stream: Stream.Stream,
  _signature: Definitions.Signature,
  _patternCache: { [string]: string },

  readInt: (Deserializer) -> number,
  readInstructions: (Deserializer, Definitions.Prototype) -> { Definitions.Instruction },
  readConstant: (Deserializer, Definitions.Prototype) -> { Definitions.Constant },
  readPrototype: (Deserializer, Definitions.Prototype?) -> Definitions.Prototype,
  readLocals: (Deserializer, Definitions.Prototype) -> { Definitions.Local },
  deserialize: (Deserializer) -> Definitions.Chunk,
} & typeof(setmetatable({}, {}))

-- from lobject.c, converts a "floating point byte" back into an integer
local function fb2int(x: number): number
  local e = bit32.band(bit32.rshift(x, 3), 31)
  if e == 0 then
    return x
  else
    return bit32.lshift(bit32.band(x, 7) + 8, e - 1)
  end
end

--- Read an integer with the size from the signature
---@return number int Resulting integer
function Deserializer:readInt(): number
  return self._stream:readPattern(self._patternCache["int"])
end

--- Read a list of unsigned 32-bit instructions, then extract all possible fields
---@param parent Definitions.Prototype Parent prototype
---@return array instructions Resulting array of instructions
function Deserializer:readInstructions(parent: Definitions.Prototype): { Definitions.Instruction }
  local sizeCode = self:readInt()
  local code = table.create(sizeCode)

  local raws = { self._stream:readPattern(string.rep("I4", sizeCode)) }
  for _, raw in ipairs(raws) do
    local ins = {
      parent = parent,
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

    table.insert(code, ins)
  end

  return code
end

--- Read a list of Lua constants
---@param parent Definitions.Prototype Parent prototype
---@return array constants Resulting array of constants
function Deserializer:readConstants(parent: Definitions.Prototype): { Definitions.Constant }
  local sizeCons = self:readInt()
  local consts = table.create(sizeCons)

  for _ = 1, sizeCons do
    local typeByte = self._stream:readPattern("B")
    local cons: Definitions.Constant = {
      parent = parent,
      type = assert(Definitions.constantTypes[typeByte], `Invalid constant type {typeByte}`),
    }

    if typeByte == 1 then -- LUA_TBOOLEAN
      cons.value = self._stream:readByte() ~= 0
    elseif typeByte == 3 then -- LUA_TNUMBER
      cons.value = self._stream:readPattern(self._patternCache["number"])
    elseif typeByte == 4 then -- LUA_TSTRING
      cons.value = string.sub(self._stream:readPattern(self._patternCache["string"]), 1, -2)
    else -- LUA_TNIL
      cons.value = nil
    end

    table.insert(consts, cons)
  end

  return consts
end

--- Read a Lua prototype and its children
---@param parent Definitions.Prototype? Parent prototype
---@return Definitions.Prototype proto Resulting prototype
function Deserializer:readPrototype(parent: Definitions.Prototype?): Definitions.Prototype
  -- read basic proto data
  local source: string, firstLine, lastLine, numUpvals, numParams, varargFlag, stackSize =
    self._stream:readPattern(self._patternCache["prototype"])

  -- fix source name
  if #source > 0 then
    source = string.sub(source, 1, -2) :: string
  end

  local proto = {
    parent = parent,
    source = source,
    firstLine = firstLine,
    lastLine = lastLine,
    numUpvals = numUpvals,
    numParams = numParams,
    isVararg = varargFlag,
    stackSize = stackSize,
  }

  -- read instructions
  local code = self:readInstructions(proto)
  proto.code = code

  -- read constants
  local consts = self:readConstants(proto)
  proto.consts = consts

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

    if inst.op == 10 then -- decode NEWTABLE array size
      inst.kB = fb2int(inst.B) -- set array size as a constant for the VM to use later
    end
  end

  -- read child prototypes
  local sizeP = self:readInt()
  local protos = table.create(sizeP)
  for _ = 1, sizeP do
    table.insert(protos, self:readPrototype(proto))
  end
  proto.protos = protos

  -- read line numbers
  local sizeLines = self:readInt()
  local linePattern = string.rep(self._patternCache["int"], sizeLines)
  proto.lines = { self._stream:readPattern(linePattern) }

  -- read local variables
  proto.locals = self:readLocals()

  -- read upvalue names
  local sizeUpvals = self:readInt()
  local upvalPattern = string.rep(self._patternCache["string"], sizeUpvals)
  local upvalues = { self._stream:readPattern(upvalPattern) }

  -- remove trailing \0
  for i, upval in ipairs(upvalues) do
    upvalues[i] = string.sub(upval, 1, -2)
  end

  proto.upvalues = upvalues

  return proto
end

--- Read a Lua local variable
---@param parent Definitions.Prototype Parent prototype
---@return array locals Resulting array of local variables
function Deserializer:readLocals(parent: Definitions.Prototype): { Definitions.Local }
  local sizeVar = self:readInt()
  local vars = table.create(sizeVar)

  for _ = 1, sizeVar do
    local name, startPc, endPc = self._stream:readPattern(self._patternCache["local"])
    table.insert(vars, {
      parent = parent,
      name = string.sub(name, 1, -2),
      startPc = startPc,
      endPc = endPc,
    })
  end

  return vars
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
    integral = integral == 1,
  }

  -- set stream's endianness
  stream.endian = if signature.endian then "<" else ">"

  -- cache certain patterns
  local patternCache = {}
  patternCache["int"] = `I{sizeInt}`
  patternCache["string"] = `s{sizeSizeT}`
  patternCache["number"] = if sizeNumber == 4 then "f" else "d"
  patternCache["prototype"] = `{patternCache["string"]}{patternCache["int"]}{patternCache["int"]}BBBB`
  patternCache["local"] = `{patternCache["string"]}{patternCache["int"]}{patternCache["int"]}`

  local self = {
    _stream = stream,
    _signature = signature,
    _patternCache = patternCache,
  }

  return setmetatable(self :: any, Deserializer) :: Deserializer
end

return Deserializer
