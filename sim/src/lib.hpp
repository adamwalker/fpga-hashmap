#pragma once
#include <Vhashmap.h>
#include <verilated_fst_c.h>

std::unique_ptr<VerilatedContext> new_context_unique();
std::unique_ptr<Vhashmap> new_vhashmap_unique(VerilatedContext& context);
std::unique_ptr<VerilatedFstC> new_fstc_unique();
void trace_ever_on(bool on);

void set_clk(Vhashmap& vhashmap, uint8_t clk);
void set_insert(Vhashmap& vhashmap, uint8_t insert);
uint8_t get_busy(Vhashmap& vhashmap);
void set_ins_key(Vhashmap& vhashmap, uint32_t ins_key);
void set_ins_value(Vhashmap& vhashmap, uint32_t ins_value);
void set_lookup(Vhashmap& vhashmap, uint8_t lookup);
void set_key(Vhashmap& vhashmap, uint32_t key);
void set_modify(Vhashmap& vhashmap, uint8_t modify);
void set_del(Vhashmap& vhashmap, uint8_t del);
void set_mod_value(Vhashmap& vhashmap, uint32_t mod_value);
uint8_t get_valid(Vhashmap& vhashmap);
uint32_t get_value(Vhashmap& vhashmap);
