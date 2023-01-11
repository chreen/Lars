--!strict

-- shared definition file for deserializer & interpreter

--#region deserializer defs
export type Chunk = {
  signature: Signature,
  head: Prototype,
}

export type Signature = {
  header: string,
  version: number,
  official: boolean,
  endian: boolean,
  int: number,
  size_t: number,
  instruction: number,
  lua_Number: number,
  integral: boolean,
}

export type ConstantType = "LUA_TNIL" | "LUA_TBOOLEAN" | "LUA_TNUMBER" | "LUA_TSTRING"
export type ConstantValue = nil | boolean | number | string

export type Prototype = {
  parent: Prototype?,
  source: string,
  firstLine: number,
  lastLine: number,
  numUpvals: number,
  numParams: number,
  isVararg: number,
  stackSize: number,
  code: { Instruction },
  consts: { Constant },
  protos: { Prototype },
  lines: { number },
  locals: { Local },
  upvalues: { string },
}

export type Instruction = {
  parent: Prototype,
  raw: number,
  op: number,
  A: number,
  B: number,
  Bx: number,
  sBx: number,
  C: number,

  isRkB: boolean,
  isRkC: boolean,
  kB: ConstantValue?,
  kC: ConstantValue?,
}

export type Constant = {
  parent: Prototype,
  type: ConstantType,
  value: ConstantValue,
}

export type Local = {
  parent: Prototype,
  name: string,
  startPc: number,
  endPc: number,
}

--#endregion

return {
  --#region deserializer data
  constantTypes = {
    [0] = "LUA_TNIL",
    [1] = "LUA_TBOOLEAN",
    [3] = "LUA_TNUMBER",
    [4] = "LUA_TSTRING",
  } :: { ConstantType },
  bxOpArgK = { -- mode == iABx && B = OpArgK
    [1] = true,
    [5] = true,
    [7] = true,
  },
  bOpArgK = { -- B == OpArgK
    [9] = true,
    [12] = true,
    [13] = true,
    [14] = true,
    [15] = true,
    [16] = true,
    [17] = true,
    [23] = true,
    [24] = true,
    [25] = true,
  },
  cOpArgK = { -- C == OpArgK
    [6] = true,
    [9] = true,
    [11] = true,
    [12] = true,
    [13] = true,
    [14] = true,
    [15] = true,
    [16] = true,
    [17] = true,
    [23] = true,
    [24] = true,
    [25] = true,
  },
  --#endregion
}
