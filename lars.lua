--!strict

-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

--#region typedefs
type Stream = {
	source: string,
	index: number
}

type Array<T> = {[number]: T}
type Dictionary<T, T2> = {[T]: T2}

type Prototype = { -- varargFlag, locals, and upvals currently unused
	source:     string,
	firstLine:  number,
	lastLine:   number,
	numUpvs:    number,
	numParams:  number,
	varargFlag: number,
	stackSize:  number,
	code:       Array<Instruction>,
	consts:     Array<Constant>,
	protos:     Array<Prototype>,
	locals:     Array<Local>,
	upvals:     Array<string>
}

type Instruction = {
	raw:  number,
	op:   number,
	A:    number,
	B:    number,
	Bx:   number,
	sBx:  number,
	C:    number,
	line: number?,
	isKb: boolean,
	isKc: boolean,
	consB: any,
	consC: any
}

type Constant = {
	type:   number,
	value:  nil | string | number | boolean
}

type Local = { -- not used for anything right now, but for parity's sake
	varName:  string,
	startPc:  number,
	endPc:    number
}

type Closure = {
	code: Array<Instruction>,
	protos: Array<Prototype>,
	upvals: Array<Upvalue>,
	vararg: Vararg,
	env: Dictionary<string, any>,
	stack: Array<any>,
	pc: number
}

type Vararg = {
	size: number,
	args: Array<any>
}

type Upvalue = {
	base: Array<any> | Upvalue, -- self-reference when closed
	idx: any,
	value: any
}

type Error = {
	pc: number,
	source: string,
	code: Array<Instruction>,
	message: string
}
--#endregion

--#region opmode arrays
local bxOpArgK: Array<boolean> = { -- mode == iABx && B = OpArgK
	[1] = true, [5] = true, [7] = true
}
local bOpArgK: Array<boolean> = { -- B == OpArgK
	[9] = true, [12] = true, [13] = true,
	[14] = true, [15] = true, [16] = true,
	[17] = true, [23] = true, [24] = true,
	[25] = true
}
local cOpArgK: Array<boolean> = { -- C == OpArgK
	[6] = true, [9] = true, [11] = true,
	[12] = true, [13] = true, [14] = true,
	[15] = true, [16] = true, [17] = true,
	[23] = true, [24] = true, [25] = true
}
--#endregion

--#region stream functions
local function newStream(src: string): Stream
	return {
		source = src,
		index = 1
	}
end

local function read(stm: Stream, len: number?): ...number?
	local rLen: number = len or 1
	local idx: number = stm.index

	stm.index += rLen
	return string.byte(stm.source, idx, idx + rLen - 1)
end

local function readInt(stm: Stream, size: number?): number
	local rSize: number = (size or 4) - 1
	local ret: number = 0

	for i = 0, rSize do
		ret += (read(stm) :: number) * 0x100^i
	end

	return ret
end

local function readString(stm: Stream, len: number?): string
	local rLen: number = len or readInt(stm)
	local idx: number = stm.index

	stm.index += rLen
	return string.sub(stm.source, idx, idx + rLen - 1)
end

local function readLString(stm: Stream): string
	return string.sub(readString(stm), 1, -2)
end

local function readDouble(stm: Stream): number
	local b: Array<number> = {read(stm, 8)} :: Array<number> -- what
		local b7, b8 = b[7], b[8]

	local sign = (-1) ^ bit32.rshift(b8, 7)
	local exp = bit32.lshift(bit32.band(b8, 0x7F), 4) + bit32.rshift(b7, 4)
	local frac = bit32.band(b7, 0x0F) * 2 ^ 48
	local normal = 1

	frac = frac + (b[6] * 2 ^ 40) + (b[5] * 2 ^ 32) + (b[4] * 2 ^ 24) + (b[3] * 2 ^ 16) + (b[2] * 2 ^ 8) + b[1]

	if (exp == 0) then
		if (frac == 0) then
			return sign * 0
		else
			normal = 0
			exp = 1
		end
	elseif (exp == 0x7FF) then
		if (frac == 0) then
			return sign * (1 / 0)
		else
			return sign * (0 / 0)
		end
	end

	return sign * 2 ^ (exp - 1023) * (normal + frac / 2 ^ 52)
end
--#endregion

--#region deserializer
local function decodeInstruction(ins: number): Instruction
	return {
		raw = ins,
		op = bit32.extract(ins, 0, 6),
		A = bit32.extract(ins, 6, 8),
		C = bit32.extract(ins, 14, 9),
		B = bit32.extract(ins, 23, 9),
		Bx = bit32.extract(ins, 14, 18),
		sBx = bit32.extract(ins, 14, 18) - 131071,
		line = nil, -- define later if lineinfo present
		isKb = false,
		isKc = false,
		consB = nil,
		consC = nil
	}
end

local function readInstructions(stm: Stream): Array<Instruction>
	local sizeCode = readInt(stm)
	local code: Array<Instruction> = table.create(sizeCode)

	for _ = 1, sizeCode do
		local inst: Instruction = decodeInstruction(readInt(stm))

		inst.isKb = bOpArgK[inst.op] and inst.B > 0xFF
		inst.isKc = cOpArgK[inst.op] and inst.C > 0xFF

		table.insert(code, inst)
	end

	return code
end

local function readConstants(stm: Stream): Array<Constant>
	local sizeK = readInt(stm)
	local consts: Array<Constant> = table.create(sizeK)

	for _ = 1, sizeK do
		local t: number = read(stm) or 0
		local val : nil | string | number | boolean

		if (t == 1) then -- boolean
			val = read(stm) ~= 0
		elseif (t == 3) then -- number
			val =  readDouble(stm)
		elseif (t == 4) then -- string
			val = readLString(stm)
		end

		table.insert(consts, {
			type = t,
			value = val
		})
	end

	return consts
end

local function readLocals(stm: Stream): Array<Local>
	local sizeLocals: number = readInt(stm)
	local locals: Array<Local> = table.create(sizeLocals)

	for _ = 1, sizeLocals do
		table.insert(locals, {
			varName = readLString(stm),
			startPc = readInt(stm),
			endPc = readInt(stm)
		})
	end

	return locals
end

local function readUpvals(stm: Stream): Array<string>
	local sizeUpvals: number = readInt(stm)
	local upvals: Array<string> = table.create(sizeUpvals)

	for _ = 1, sizeUpvals do
		table.insert(upvals, readLString(stm))
	end

	return upvals
end

local function readProto(stm: Stream): Prototype
	local source: string = readLString(stm)
	if (#source == 0) then
		source = "@Lars"
	end

	local firstLine: number = readInt(stm)
	local lastLine: number = readInt(stm)

	local numUpvs, numParams, varargFlag, stackSize = read(stm, 4)

	local code = readInstructions(stm)
	local consts = readConstants(stm)

	for _, inst in pairs(code) do -- finish preloading constants
		if (bxOpArgK[inst.op]) then
			inst.consB = consts[inst.Bx + 1].value
			continue -- iABx, skip B & C fields
		end

		if (inst.isKb) then
			inst.consB = consts[inst.B - 0xFF].value
		end

		if (inst.isKc) then
			inst.consC = consts[inst.C - 0xFF].value
		end
	end

	local sizeProtos: number = readInt(stm)
	local protos: Array<Prototype> = table.create(sizeProtos)
	for _ = 1, sizeProtos do
		table.insert(protos, readProto(stm))
	end

	local sizeLines: number = readInt(stm)
	for idx = 1, sizeLines do
		code[idx].line = readInt(stm)
	end

	local locals = readLocals(stm)
	local upvals = readUpvals(stm)

	return {
		source = source,
		firstLine = firstLine,
		lastLine = lastLine,
		numUpvs = numUpvs :: number,
		numParams = numParams :: number,
		varargFlag = varargFlag :: number,
		stackSize = stackSize or 255,
		code = code,
		consts = consts,
		protos = protos,
		locals = locals,
		upvals = upvals
	}
end

--- Deserializes a bytecode string into a prototype that can
--- be wrapped into a closure
---@param bytecode string Lua 5.1 bytecode
---@return table proto Deserialized prototype
local function deserialize(bytecode: string): Prototype
	-- create stream
	local stm = newStream(bytecode)

	-- check header
  -- TODO: support more formats
	assert(readString(stm, 4) == "\27Lua",  "invalid bytecode signature")
	assert(read(stm) == 0x51,               "invalid bytecode version")
	assert(read(stm) == 0x00,               "invalid bytecode format")
	assert(read(stm) == 0x01,               "invalid bytecode endianness")
	assert(read(stm) == 0x04,               "invalid int size")
	assert(read(stm) == 0x04,               "invalid size_t size")
	assert(read(stm) == 0x04,               "invalid instruction size")
	assert(read(stm) == 0x08,               "invalid lua_Number size")
	assert(read(stm) == 0x00,               "invalid integral flag")

	-- deserialize & return top-level prototype
	return readProto(stm)
end
--#endregion

--#region interpreter
local function closeUpvalues(uvlist: Array<Upvalue>, from: number)
	for i, uv in pairs(uvlist) do
		if (i < from) then
			continue
		end

		uv.value = (uv.base :: Array<any>)[uv.idx :: number]
		uv.base = uv
		uv.idx = "value"
	end
end

local function getUpval(uv: Upvalue)
	if (uv.idx == "value") then
		return (uv.base :: Upvalue).value
	else
		return (uv.base :: Array<any>)[uv.idx :: number]
	end
end

local function setUpval(uv: Upvalue, val: any)
	if (uv.idx ~= "value") then
		(uv.base :: Array<any>)[uv.idx :: number] = val
	end
end

local wrapPrototype: (Prototype, Dictionary<string, any>, Array<Upvalue>?) -> (...any) -> ...any

local function executeClosure(cl: Closure): ...any
	local code = cl.code
	local protos = cl.protos
	local upvals = cl.upvals
	local vararg = cl.vararg
	local env = cl.env

	local stack = cl.stack
	local pc = cl.pc
	local stackTop = -1
	local openUpvs: Array<Upvalue> = {}

	while (true) do
		local inst = code[pc]
		local op = inst.op
		pc += 1

		if (op < 12) then -- 0-11
			if op < 5 then
				if op < 2 then
					if op > 0 then -- LOADK
						stack[inst.A] = inst.consB
					else -- MOVE
						stack[inst.A] = stack[inst.B]
					end
				elseif op > 2 then
					if op < 4 then -- LOADNIL
						for i = inst.A, inst.B do
							stack[i] = nil
						end
					else -- GETUPVAL
						stack[inst.A] = getUpval(upvals[inst.B])
					end
				else -- LOADBOOL
					stack[inst.A] = inst.B ~= 0

					if (inst.C ~= 0) then
						pc += 1
					end
				end
			elseif op > 5 then
				if op < 9 then
					if op < 7 then -- GETTABLE
						local key

						if (inst.isKc) then
							key = inst.consC
						else
							key = stack[inst.C]
						end

						stack[inst.A] = stack[inst.B][key]
					elseif op > 7 then -- SETUPVAL
						setUpval(upvals[inst.B], stack[inst.A])
					else -- SETGLOBAL
						env[inst.consB] = stack[inst.A]
					end
				elseif op > 9 then
					if op < 11 then -- NEWTABLE
						stack[inst.A] = {}
					else -- SELF
						local A = inst.A
						local tab = stack[inst.B]
						local key

						if (inst.isKc) then
							key = inst.consC
						else
							key = stack[inst.C]
						end

						stack[A + 1] = tab
						stack[A] = tab[key]
					end
				else -- SETTABLE
					local key, val

					if (inst.isKb) then
						key = inst.consB
					else
						key = stack[inst.B]
					end

					if (inst.isKc) then
						val = inst.consC
					else
						val = stack[inst.C]
					end

					stack[inst.A][key] = val
				end
			else -- GETGLOBAL
				stack[inst.A] = env[inst.consB]
			end
		elseif (op < 18) then -- 12-17
			local lhs, rhs

			if (inst.isKb) then
				lhs = inst.consB
			else
				lhs = stack[inst.B]
			end

			if (inst.isKc) then
				rhs = inst.consC
			else
				rhs = stack[inst.C]
			end

			if op < 14 then
				if op > 12 then -- SUB
					stack[inst.A] = lhs - rhs
				else -- ADD
					stack[inst.A] = lhs + rhs
				end
			elseif op > 14 then
				if op < 16 then -- DIV
					stack[inst.A] = lhs / rhs
				elseif op > 16 then -- POW
					stack[inst.A] = lhs ^ rhs
				else -- MOD
					stack[inst.A] = lhs % rhs
				end
			else -- MUL
				stack[inst.A] = lhs * rhs
			end
		else -- 18-37
			if op < 27 then
				if op < 22 then
					if op < 19 then -- UNM
						stack[inst.A] = -stack[inst.B]
					elseif op > 19 then
						if op < 21 then -- LEN
							stack[inst.A] = #stack[inst.B]
						else -- CONCAT
							local s = ""
							for idx = inst.B, inst.C do
								s ..= stack[idx]
							end
							stack[inst.A] = s
						end
					else -- NOT
						stack[inst.A] = not stack[inst.B]
					end
				elseif op > 22 then
					if (op > 25) then -- TEST
						if (not stack[inst.A]) ~= (inst.C ~= 0) then pc = pc + code[pc].sBx end
						pc = pc + 1
						continue -- avoid EQ/LT/LE code
					end

					local lhs, rhs

					if (inst.isKb) then
						lhs = inst.consB
					else
						lhs = stack[inst.B]
					end

					if (inst.isKc) then
						rhs = inst.consC
					else
						rhs = stack[inst.C]
					end

					if op < 25 then
						if op > 23 then -- LT
							if (lhs < rhs) == (inst.A ~= 0) then
								pc += code[pc].sBx
							end
						else -- EQ
							if (lhs == rhs) == (inst.A ~= 0) then
								pc += code[pc].sBx
							end
						end
					else -- LE
						if (lhs <= rhs) == (inst.A ~= 0) then
							pc += code[pc].sBx
						end
					end

					pc += 1 -- save space
				else -- JMP
					pc += inst.sBx
				end
			elseif op > 27 then
				if op < 33 then
					if op < 30 then
						if op > 28 then -- TAILCALL
							closeUpvalues(openUpvs, 0)

							local A = inst.A
							local B = inst.B
							local params

							if (B == 0) then
								params = stackTop - A
							else
								params = B - 1
							end

							return stack[A](table.unpack(stack, A + 1, A + params))
						else -- CALL
							local A = inst.A
							local B = inst.B
							local C = inst.C
							local params

							if (B == 0) then
								params = stackTop - A
							else
								params = B - 1
							end

							local returnList = table.pack(stack[A](table.unpack(stack, A + 1, A + params)))
							local returnSize = returnList.n

							if (C == 0) then
								stackTop = A + returnSize - 1
							else
								returnSize = C - 1
							end

							table.move(returnList, 1, returnSize, A, stack)
						end
					elseif op > 30 then
						if op < 32 then -- FORLOOP
							local A = inst.A
							local step = stack[A + 2]
							local index = stack[A] + step
							local limit = stack[A + 1]
							local loops

							if (step == math.abs(step)) then
								loops = index <= limit
							else
								loops = index >= limit
							end

							if (loops) then
								stack[A] = index
								stack[A + 3] = index
								pc += inst.sBx
							end
						else -- FORPREP
							local A = inst.A
							local init, limit, step

							init = assert(tonumber(stack[A]), '`for` initial value must be a number')
							limit = assert(tonumber(stack[A + 1]), '`for` limit must be a number')
							step = assert(tonumber(stack[A + 2]), '`for` step must be a number')

							stack[A] = init - step
							stack[A + 1] = limit
							stack[A + 2] = step

							pc += inst.sBx
						end
					else -- RETURN
						closeUpvalues(openUpvs, 0)

						local A = inst.A
						local B = inst.B
						local len

						if (B == 0) then
							len = stackTop - A + 1
						else
							len = B - 1
						end

						return table.unpack(stack, A, A + len - 1)
					end
				elseif op > 33 then
					if op < 36 then
						if op > 34 then -- CLOSE
							closeUpvalues(openUpvs, inst.A)
						else -- SETLIST
							local A = inst.A
							local C = inst.C
							local len = inst.B
							local tab = stack[A]

							if (len == 0) then
								len = stackTop - A
							end

							if (C == 0) then
								C = code[pc].raw
								pc += 1
							end

							local offset = (C - 1) * 50

							table.move(stack, A + 1, A + len, offset + 1, tab)
						end
					elseif op > 36 then -- VARARG
						local A = inst.A
						local B = inst.B

						if (B == 0) then
							B = vararg.size
							stackTop = A + B - 1
						end

						table.move(vararg.args, 1, B, A, stack)
					else -- CLOSURE
						local sub = protos[inst.Bx + 1]
						local uvCount = sub.numUpvs
						local uvList

						if (uvCount > 0) then
							uvList = table.create(uvCount)

							for i = 1, uvCount do
								local pseudo = code[pc + i - 1]

								if (pseudo.op == 0) then -- MOVE
									local uv = openUpvs[pseudo.B]

									if (not uv) then
										uv = {
											base = stack,
											idx = pseudo.B,
											value = nil
										}
										uvList[i - 1] = uv
									end
								else -- GETUPVAL
									uvList[i - 1] = upvals[pseudo.B]
								end
							end

							pc += uvCount
						end

						stack[inst.A] = wrapPrototype(sub, env, uvList)
					end
				else -- TFORLOOP
					local A = inst.A
					local func = stack[A]
					local first = stack[A + 1]
					local second = stack[A + 2]
					local base = A + 3

					stack[base + 2] = second
					stack[base + 1] = first
					stack[base] = func

					local vals = {func(first, second)}

					table.move(vals, 1, inst.C, base, stack)

					if (stack[base] ~= nil) then
						stack[A + 2] = stack[base]
						pc += code[pc].sBx
					end

					pc += 1
				end
			else -- TESTSET
				local B = inst.B

				if (not stack[B]) ~= (inst.C ~= 0) then
					stack[inst.A] = stack[B]
					pc += code[pc].sBx
				end

				pc += 1
			end
		end

		cl.pc = pc
	end
end

local function handleError(err: Error)
	local line = tostring(err.code[err.pc - 1].line or "?")
	return error(string.format("%s:%s: %s", err.source, line, err.message), 0)
end

--- Wraps a prototype into a new Closure and returns
--- a function to execute it
---@param proto Prototype Prototype to wrap
---@param env table Environment table
---@param upv table Upvalue table, used internally
---@return function execute Execute function, accepts arguments
wrapPrototype = function(proto: Prototype, env: Dictionary<string, any>, upv: Array<Upvalue>?): (...any) -> ...any
	return function(...)
		local args = table.pack(...)
		local upvals: Array<Upvalue> = upv or {}
		local vararg: Vararg = {size = 0, args = {}}
		local stack: Array<any> = table.create(proto.stackSize)

		-- load parameters to the stack
		table.move(args, 1, proto.numParams, 0, stack)

		-- add extra arguments to vararg list
		if (proto.numParams < args.n) then
			local startIdx = proto.numParams + 1
			local len = args.n - proto.numParams

			vararg.size = len
			table.move(args, startIdx, startIdx + len - 1, 1, vararg.args)
		end

		local closure: Closure = {
			code = proto.code,
			protos = proto.protos,
			upvals = upvals,
			vararg = vararg,
			env = env,
			stack = stack,
			pc = 1
		}

		local res = table.pack(pcall(executeClosure, closure))

		if (res[1]) then
			return table.unpack(res, 2, res.n)
		else
			local err: Error = {
				pc = closure.pc,
				source = proto.source,
				code = closure.code,
				message = res[2]
			}

			return handleError(err)
		end
	end
end
--#endregion

return {
	deserialize = deserialize,
	wrap = wrapPrototype
}