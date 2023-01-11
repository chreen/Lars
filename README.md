Lars
====
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

## About
Lars is a collection of libraries that provide a programmatic way to manipulate Lua 5.1 bytecode in Luau.

Lars targets Roblox, but the code could be easily modified to work in another Luau environment.

## Use cases
* Re-implementing arbitrary code execution in an environment without `loadstring` or similar (bytecode compiler not included)
* Sandboxing
* Analyzing obfuscation with a custom deserializer implementation
* Modifying existing bytecode to optimize or change instructions

## Features
This project is still a work-in-progress, so not all features have been implemented yet. Planned and implemented features are listed below.

- [x] - Bytecode deserializer
- [x] - Bytecode serializer
- [ ] - Virtual machine
- [ ] - Instruction argument mapper
- [ ] - Disassembler

## Installation
**WIP, not published on Wally yet**

## Documentation
**WIP**

## Credits
[FiOne](https://github.com/Rerumu/FiOne) by Rerumu was used as the base for most of the virtual machine.
```
FiOne
Copyright (C) 2021  Rerumu

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
```

[A No-Frills Introduction to Lua 5.1 VM Instructions](http://underpop.free.fr/l/lua/docs/a-no-frills-introduction-to-lua-5.1-vm-instructions.pdf)
by Kein-Hong Man, esq. provided a great deal of insight into Lua's internals, and is the foundation of my own knowledge of the bytecode format.
