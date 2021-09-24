Lars
====
![GitHub](https://img.shields.io/github/license/chreen/Lars) 

**Lars** is a Lua 5.1 bytecode interpreter written for [Luau](https://luau-lang.org/). It aims to take advantage of features exclusive to Luau and to provide relatively fast, reliable execution of bytecode.

**Lars *only* interprets bytecode, not Lua code. If you are looking to execute code, a project like [Yueliang](http://underpop.online.fr/l/lua/yueliang/) paired with Lars may be what you're looking for.**


## Usage
Below is an example usage of Lars. The string `helloworld` is the escaped bytecode for `print("Hello world!")`. Exposed functions are documented in [lars.lua](https://github.com/chreen/Lars/blob/main/lars.lua).
```lua
local lars = require(game:GetService("ReplicatedStorage"):WaitForChild("Lars"))

local helloworld = "\x1B\x4C\x75\x61\x51\x00\x01\x04\x04\x04\x08\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x02\x04\x00\x00\x00\x05\x00\x00\x00\x41\x40\x00\x00\x1C\x40\x00\x01\x1E\x00\x80\x00\x02\x00\x00\x00\x04\x06\x00\x00\x00\x70\x72\x69\x6E\x74\x00\x04\x0D\x00\x00\x00\x48\x65\x6C\x6C\x6F\x20\x77\x6F\x72\x6C\x64\x21\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
lars.wrap(lars.deserialize(helloworld), getfenv(0))() -- "Hello world!"
```


## Compatibility
Currently, Lars only supports bytecode with the following header:
* Bytecode signature: `0x1B4C7561`
* Version number: `0x51`
* Format: `0x00` (official)
* Endianness: little endian
* Int size: 4 bytes
* Size_t size: 4 bytes
* Instruction size: 4 bytes
* Lua_number size: 8 bytes
* Integral flag: 0 (floating-point)

Support for other formats will likely come at a later time.


## Credits
Lars is based on the GPL-3.0 licensed project [FiOne](https://github.com/Rerumu/FiOne) by [Rerumu](https://github.com/Rerumu).  
Part of the deserializer (double decoding) and most of the code for executing instructions has been modified from FiOne's source.

Additional information about Lua bytecode was gained through [A No-Frills Introduction to Lua 5.1 VM Instructions](http://underpop.free.fr/l/lua/docs/a-no-frills-introduction-to-lua-5.1-vm-instructions.pdf) by Kein-Hong Man.
