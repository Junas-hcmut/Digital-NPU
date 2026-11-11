// Compile order: leaf cells first, top level last.
// Usage (from the repo root): xrun -sv -f rtl/filelist.f -top npu_apb_top
rtl/arith/fa.sv
rtl/arith/RCA.sv
rtl/arith/CSA3to2.sv
rtl/arith/CSA8to2.sv
rtl/arith/mulBW.sv
rtl/mac/mac_unit.sv
rtl/mac/mac_chain.sv
rtl/mac/mac_system.sv
rtl/mem/act_buffer.sv
rtl/mem/weight_mem_load.sv
rtl/post/relu.sv
rtl/post/requant.sv
rtl/top/npu_fsm.sv
rtl/top/apb_slave_regs.sv
rtl/top/npu_ctrl_top.sv
rtl/top/npu_apb_top.sv
