# RISC-V Integrated Tiled Matrix Multiplication Accelerator

A Verilog RTL project implementing a custom matrix multiplication accelerator integrated with a five-stage RV32IM RISC-V processor. The processor is extended with a custom `MATMUL` instruction that launches an **8×8 output-stationary systolic-array accelerator** for tiled matrix multiplication.

The design includes **CSR-controlled approximate multiplication**, **banked BRAM memory**, **hazard detection**, **forwarding**, **pipeline stall control**, and an autonomous FSM-based MatMul execution unit.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Key Features](#key-features)
- [System Architecture](#system-architecture)
- [Processor Architecture](#processor-architecture)
- [Custom MATMUL Instruction](#custom-matmul-instruction)
- [CSR-Controlled Approximation](#csr-controlled-approximation)
- [Matrix Multiplication Accelerator](#matrix-multiplication-accelerator)
- [Systolic Array Architecture](#systolic-array-architecture)
- [Memory Architecture](#memory-architecture)
- [Address Generation](#address-generation)
- [FSM Controller](#fsm-controller)
- [Cycle Count and Performance](#cycle-count-and-performance)

- [Applications](#applications)

---

## Project Overview

This project demonstrates how a standard five-stage RISC-V processor can be extended with a dedicated hardware accelerator for matrix multiplication.

Instead of executing matrix multiplication completely in software, the processor only provides the base addresses of the input matrices and issues a custom `MATMUL` instruction. After that, the accelerator performs the full tiled matrix multiplication internally.

The accelerator uses an **8×8 output-stationary systolic array**, where:

- **Weights move horizontally**
- **Activations move vertically**
- **Partial sums remain inside each processing element**

This improves data reuse, reduces repeated memory access, and significantly reduces the cycle count compared to sequential scalar execution.

---

## Key Features

- **Five-stage RV32IM RISC-V processor**
- **Custom `MATMUL` instruction**
- **8×8 output-stationary systolic array**
- **64 processing elements**
- **8-bit input operands**
- **32-bit accumulated outputs**
- **CSR-controlled approximate multiplier**
- **8-bank BRAM data memory**
- **64-bit MatMul read port**
- **256-bit MatMul write port**
- **Tiled 32×32 matrix multiplication**
- **Support for padded 30×30 matrices**
- **Hazard detection and forwarding**
- **FSM-controlled accelerator execution**
- **FPGA-oriented Verilog RTL design**

---

## System Architecture

The complete system contains the following major blocks:

1. **RISC-V processor core**
2. **Instruction memory**
3. **Register file**
4. **ALU and scalar execution units**
5. **Hazard detection unit**
6. **Forwarding unit**
7. **CSR register file**
8. **8-bank BRAM data memory**
9. **Matrix multiplication accelerator**
10. **8×8 systolic array**
11. **Tile accumulator**
12. **Address generator**
13. **Writeback logic**

The processor controls instruction execution, while the MatMul accelerator performs the repeated arithmetic work required for matrix multiplication.

---

## Processor Architecture

The processor follows a classical **five-stage RV32IM pipeline**.

### 1. Instruction Fetch Stage

The instruction fetch stage reads instructions from instruction memory using the program counter. Under normal operation, the PC increments by four bytes every cycle. During a long-latency operation such as `MATMUL`, the pipeline is stalled so that no new instruction is executed until the accelerator completes.

### 2. Instruction Decode Stage

The decode stage reads instruction fields, accesses the register file, generates control signals, and identifies the custom `MATMUL` instruction.

For `MATMUL`, the operands are interpreted as memory addresses:

```text
rs1 → weight matrix base address
rs2 → input matrix base address
rd  ← output matrix base address
```

The source registers are not treated as scalar values to be multiplied. They are used as pointers to matrix regions in memory.

### 3. Execute Stage

The execute stage contains both the scalar ALU path and the matrix acceleration path.

For the `MATMUL` instruction, the execute stage captures:

```text
wt_base = rs1_data
in_base = rs2_data
```

A one-cycle start pulse is generated using edge detection:

```text
mm_start = is_matmul . ~prev_matmul
```

Here:

```text
.  = logical AND
~  = logical NOT
```

Equivalent Verilog logic:

```verilog
assign mm_start = is_matmul & ~prev_matmul;
```

This prevents the accelerator from being restarted repeatedly while the pipeline is stalled.

### 4. Memory Stage

The memory stage handles normal scalar load and store operations. The MatMul unit also accesses the same data memory through wider dedicated ports.

During MatMul execution, CPU stores are blocked so that the accelerator can safely read operand tiles and write output tiles.

### 5. Writeback Stage

For normal instructions, the writeback stage writes the ALU result, load data, jump address, or CSR result into the destination register.

For `MATMUL`, the destination register receives the output matrix base address:

```text
rd ← in_base + 1024
```

The output matrix itself remains stored in data memory.

---

## Custom MATMUL Instruction

The custom instruction behaves as:

```assembly
MATMUL rd, rs1, rs2
```

where:

```text
rs1 = weight matrix base address
rs2 = input matrix base address
rd  = output matrix base address
```

Example:

```assembly
x1 = wt_base
x2 = in_base

MATMUL x3, x1, x2
```

After completion:

```text
x3 = in_base + 1024
```

The output address offset is `1024` because the padded input matrix has:

```text
32 × 32 × 1 byte = 1024 bytes
```

---

## CSR-Controlled Approximation

The design supports approximate multiplication using a CSR-controlled error vector:

```text
mul_er[7:0]
```

This signal is distributed to all processing elements in the systolic array. Each bit controls one approximation stage inside the reconfigurable 8-bit multiplier.

| Mode | `mul_er` | Description |
|---|---:|---|
| Accurate | `8'hFF` | All stages exact |
| Approx L0 | `8'hFE` | One lower stage approximate |
| Approx L1 | `8'hC0` | Several lower stages approximate |
| Approx L2 | `8'h80` | Only MSB stage exact |
| Approx L3 | `8'h00` | All stages approximate |

This allows the same hardware to operate in either **accurate mode** or **approximate mode**, depending on the software-selected CSR value.

---

## Matrix Multiplication Accelerator
<img width="523" height="355" alt="image" src="https://github.com/user-attachments/assets/f9280f7e-8ee1-4a26-b198-0df50dbe21e8" />

The MatMul accelerator performs the full tiled matrix multiplication after receiving the `mm_start` signal.

Main internal blocks:

- **FSM controller**
- **Weight tile register**
- **Input tile register**
- **Feeder unit**
- **8×8 systolic array**
- **Tile accumulator**
- **Address generator**
- **BRAM memory interface**

Main control signals:

| Signal | Description |
|---|---|
| `start` | Starts accelerator execution |
| `busy` | Accelerator is currently active |
| `done` | Matrix multiplication is complete |
| `mm_active` | MatMul unit owns memory access |
| `mul_er` | Approximation control vector |

---

## Systolic Array Architecture

The accelerator uses an **8×8 output-stationary systolic array** containing:

```text
8 × 8 = 64 processing elements
```

Each processing element performs:

```text
psum_out ← psum_out + (w_in × a_in)
```

The update happens only when valid inputs are present:

```text
mac_en . w_valid . a_valid = 1
```

### Dataflow

```text
Weights      → move left to right
Activations  → move top to bottom
Partial sums → stay inside each PE
```

This output-stationary approach reduces partial-sum movement and improves operand reuse.

### Processing Element
<img width="403" height="324" alt="image" src="https://github.com/user-attachments/assets/a65be214-929d-4afe-934c-3223c994a94f" />

Each PE contains:

- **8-bit weight input**
- **8-bit activation input**
- **Reconfigurable 8-bit multiplier**
- **32-bit accumulator**
- **Carry-lookahead adder**
- **Weight forwarding path**
- **Activation forwarding path**
- **Valid signal forwarding**

The multiplier produces a 16-bit product, which is extended and accumulated into a 32-bit partial sum.

The 32-bit accumulator is required because the maximum value for a 30-element dot product is:

```text
30 × 255 × 255 = 1,950,750
```

This value requires more than 16 bits.

### Feeder Unit

The feeder unit supplies operands to the systolic array with diagonal timing skew.

For an 8×8 array:

```text
Feed cycles  = 8 + 8 - 1 = 15
Drain cycles = 7
Total run    = 22 cycles
```

The feeder drives:

```text
w_left_flat[63:0]
a_top_flat[63:0]
w_left_valid[7:0]
a_top_valid[7:0]
```

This ensures the correct weight and activation values meet inside the correct processing element at the correct cycle.

---

## Tiled Matrix Multiplication
<img width="437" height="385" alt="image" src="https://github.com/user-attachments/assets/857aac22-5e5b-4957-b849-06e97be1fc9b" />

The accelerator operates on **8×8 tiles**.

A 32×32 matrix is divided into:

```text
4 × 4 = 16 tiles
```

For each output tile:

```text
C[i][j] = Σ W[i][k] × A[k][j],  k = 0 to 3
```

Therefore, the full 32×32 matrix multiplication requires:

```text
4 × 4 × 4 = 64 systolic-array runs
```

For a 30×30 matrix, the operands are padded to 32×32 using zeros. This avoids special boundary hardware and allows every tile to use the same 8×8 datapath.

---

## Memory Architecture

The memory stores:

```text
Weight matrix  → W_pad[32][32]  → 8-bit
Input matrix   → A_pad[32][32]  → 8-bit
Output matrix  → C_pad[32][32]  → 32-bit
```

Base address mapping:

```text
wt_base       → weight matrix
in_base       → input matrix
in_base+1024  → output matrix
```

For 8-bit input matrices:

```text
addr = base + row × 32 + col
```

For 32-bit output matrix:

```text
addr = C_base + 4 × (row × 32 + col)
```

### 8-Bank BRAM Data Memory

The data memory is implemented using **eight 32-bit BRAM banks**.

#### CPU Access

The CPU uses a normal scalar memory interface for:

- Byte access
- Halfword access
- Word access

#### MatMul Read Access

The MatMul unit reads one row of an 8×8 operand tile using a 64-bit read port:

```text
8 × 8-bit values = 64 bits
```

#### MatMul Write Access

The MatMul unit writes one output tile row using a 256-bit write port:

```text
8 × 32-bit values = 256 bits
```

This wide memory interface allows efficient tile movement between BRAM and the accelerator.

---

## Address Generation

The accelerator uses shift-based address generation instead of multiplier-based address generation.

### Weight Tile Address

```text
W_addr = wt_base + ((tile_i × 8 + row) << 5) + tile_k × 8
```

### Input Tile Address

```text
A_addr = in_base + ((tile_k × 8 + row) << 5) + tile_j × 8
```

### Output Tile Address

```text
C_addr = C_base + ((tile_i × 8 + row) << 7) + (tile_j << 5)
```

The shifts represent fixed row strides:

```text
<< 5 = multiply by 32
<< 7 = multiply by 128
```

This keeps address generation simple and FPGA-friendly.

---

## FSM Controller

The MatMul unit is controlled by a finite-state machine.

| State | Function |
|---|---|
| `S_IDLE` | Wait for start pulse |
| `S_CLEAR_ACC` | Clear tile accumulator |
| `S_FETCH_W` | Fetch weight tile |
| `S_FETCH_A` | Fetch input tile |
| `S_CLEAR_SA` | Clear systolic array |
| `S_RUN` | Run systolic computation |
| `S_ACCUM` | Start tile accumulation |
| `S_WAIT_ACCUM` | Wait for row-wise accumulation |
| `S_NEXT_K` | Move to next inner tile |
| `S_WRITE_C` | Write output tile |
| `S_NEXT_TILE` | Move to next output tile |
| `S_DONE` | Signal completion |

The FSM makes accelerator behavior deterministic and easy to verify.

---

## Tile Accumulator

Each output tile receives contributions from four inner tile multiplications.

```text
C_tile = partial_0 + partial_1 + partial_2 + partial_3
```

The updated accumulator uses **8 adders** instead of 64 parallel adders. It processes one row of the 8×8 output tile per cycle.

```text
64 outputs = 8 rows × 8 columns
```

Each accumulation event takes 8 cycles. This reduces hardware area while maintaining structured operation.

---

## Cycle Count and Performance

For one inner tile step:

| Operation | Cycles |
|---|---:|
| Fetch weight tile | 10 |
| Fetch input tile | 10 |
| Clear systolic array | 1 |
| Run systolic array | 22 |
| Start accumulation | 1 |
| Wait row-wise accumulation | 8 |
| Advance inner tile | 1 |
| **Total** | **53** |

For one complete output tile:

```text
1 + 4 × 53 + 8 + 1 = 222 cycles
```

For all 16 output tiles:

```text
16 × 222 = 3552 cycles
```

Including start and done overhead:

```text
Total ≈ 3554 cycles
```

### Comparison

| Design | Cycle Count |
|---|---:|
| Without systolic array | 32768 cycles |
| With 8×8 systolic array | ≈ 3554 cycles |

Approximate speedup:

```text
32768 / 3554 ≈ 9.2×
```

---






## Applications

This project is useful for:

- Matrix multiplication acceleration
- Neural-network inference
- FPGA-based AI accelerators
- Digital signal processing
- Image filtering
- Approximate-computing research
- RISC-V custom instruction design
- Computer architecture education
- VLSI and RTL design learning

The design demonstrates how custom instructions and specialized datapaths can accelerate repetitive numerical workloads while preserving a clean processor-level programming model.
