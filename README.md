# FISC
FISC - Flexible Instruction Set Computer - Is the new Instruction Set Architecture inspired by ARMv8 and x86-64.

# Overview
FISC is a Central Processing Unit Architecture being developed for multiple environments and implementations, such as FPGAs, ASICs and Virtual Machines.

It also comprises the entire environment and ecosystem being designed for the CPU. In other words, FISC is the combination of the Instruction Set, Microarchitecture and the tools being created for it such as the assembler, disassembler, compiler and debugger.

The name of each feature / subproject is subject to future change.

# Overall Specifications
This architecture is heavily influenced by ARMv8, specifically ARMv8-A. 
It also carries a lot of design decisions featured in x86-64. It is for this reason why the architecture is named FISC - Flexible Instruction Set Computer.

The first iteration of this project develops a very simple R/CISC architecture and yet powerful design. In this first version, the following specifications can be found:

> 1- **Architecture type**: RISC with CISC features (mostly RISC)  
> 2- **Computing widt**h: 64 bits  
> 3- **Core count**: Single core (1 core)  
> 4- **Computing model**:  
	4.1- Von Neumann  
	4.2- Scalar and Vectorized (SISD on General purpose registers + SIMD on FPU)  
	4.3- In order execution  
	4.4- Stack + Register-Register + Register-Memory Machine  
> 5- **Thread count**:  1 thread  
> 6- **Pipeline depth**: 5 stages (IF/ID/EX/MEM/WB)  
> 7- **Pipeline schedule**: Static In-Order Single issue  
> 8- **Decode mechanism**: Microcoded (CISC feature)  
> 9- **Register count**: 32 GPR (General Purpose Registers); 13 SCR (Special Control Registers); Each register is 64-bits with some exceptions on the SCR  
> 10- **Branch Prediction support**: No  
> 11- **Prefetching and Predecoding support**: No  
> 12- **Cache count**: L1 only (this will vary in the future)  
> 13- **L1 Instruction Cache size**: 2KiB (subject to change)  
> 14- **L1 Instruction Size properties**: Set Associative, 2 Way, 32 Sets, 32 byte data block (2 x 32 x 32 = 2048 bytes = 2 KiB)  
> 15- **L1 Data Cache size**: 2 KiB (subject to change)  
> 16- **L1 Data Cache properties**: Set Associative, 2 Way, 32 Sets, 32 byte data block (2 x 32 x 32 = 2048 bytes = 2 KiB)  
>  17- **Virtual Memory support**: Yes  
>  18- **Virtual Memory TLB Cache size**: *\*TO DETERMINE**  
>  19- **Floating Point Unit support**: Yes  
>  20- **Interrupts and Exceptions support**: Yes  
>  21- **Instruction count**: 109 (updated: 19/02/2017 @ 18:33)  
	21.1- Arithmetic and Logic  
	21.2- Branching  
	21.3- Load and Store  
	21.4- FPU  
	21.5- CPU Status Control  
	21.6- Interrupts  
	21.7- Virtual Memory  


# Full System Design
![FullSystem](http://i.imgur.com/nLzs2qY.png)

# Instruction Set Architecture
<p align="center"><img src="http://i.imgur.com/34WnYw9.png"></p>

# Microarchitecture

The pipelined Microarchitecture can be described by the following diagram:
![High Level Microarchitecture](http://i.imgur.com/9wLWx8X.png)
5 main components are present:
> 1- Stage 1: **Fetch**  
> 2- Stage 2: **Decode**  
> 3- Stage 3: **Execute**  
> 4- Stage 4: **Memory Access**  
> 5- Stage 5: **Write Back**  

<a href="http://i.imgur.com/rQ2PIP2.png"><img src="http://i.imgur.com/rQ2PIP2.png" align="left" height="470" width="495" ></a>
<a href="http://i.imgur.com/j9GLU1Y.png"><img src="http://i.imgur.com/j9GLU1Y.png" align="left" height="428" width="495" ></a>
<a href="http://i.imgur.com/A0u5QPA.png"><img src="http://i.imgur.com/A0u5QPA.png" align="left" height="428" width="495" ></a>
<a href="http://i.imgur.com/s5U3T6v.png"><img src="http://i.imgur.com/s5U3T6v.png" align="left" height="400" width="600" ></a>
<a href="http://i.imgur.com/IzolzTa.png"><img src="http://i.imgur.com/IzolzTa.png" align="left" height="485" width="300" ></a>
