# EE2026-Graphing-Calculator
FPGA-based graphing calculator for EE2026, implemented in Verilog on the Basys3 board with OLED display and PS/2 mouse input.

This project is an FPGA-based graphing calculator designed for the EE2026 Digital Design module.  
It is fully implemented in **Verilog** and runs on the **Basys3** FPGA board.

## 🔧 Overview

- Written entirely in **Verilog HDL**
- Target board: **Digilent Basys3 (Artix-7 FPGA)**
- Display: **OLED module** connected via JC port
- Input: **PS/2 wireless mouse** for UI navigation and selection

## ✨ Features

- Integer and fixed-point arithmetic operations (+, −, ×, ÷)
- Polynomial and function plotting on the OLED display
- Interactive keypad / UI controlled by the mouse
- Radix conversion and result visualization
- Modular Verilog design:
  - Top-level integration module (`Top_Student.v`)
  - Arithmetic units (`addsub_function`, `muldiv_function`, etc.)
  - Graph plotting engine (`Graph_Plot`)
  - Mouse and display controller modules

## 🧠 Verilog Focus

The project demonstrates:
- Hierarchical Verilog design and module instantiation  
- Finite State Machines for UI control flow  
- Fixed-point arithmetic and scaling for graphing  
- Clock division and timing control for Basys3  
- Hardware debugging using LEDs and seven-seg display

