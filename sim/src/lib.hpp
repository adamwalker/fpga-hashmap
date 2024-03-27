#pragma once
#include <Vkvs.h>
#include <verilated_fst_c.h>

std::unique_ptr<VerilatedContext> new_context_unique();
std::unique_ptr<Vkvs> new_vkvs_unique(VerilatedContext& context);
std::unique_ptr<VerilatedFstC> new_fstc_unique();
void trace_ever_on(bool on);

void set_clk(Vkvs& vkvs, uint8_t clk);
void set_insert(Vkvs& vkvs, uint8_t insert);
uint8_t get_busy(Vkvs& vkvs);
void set_ins_key(Vkvs& vkvs, uint32_t ins_key);
void set_ins_value(Vkvs& vkvs, uint32_t ins_value);
void set_lookup(Vkvs& vkvs, uint8_t lookup);
void set_key(Vkvs& vkvs, uint32_t key);
void set_modify(Vkvs& vkvs, uint8_t modify);
void set_del(Vkvs& vkvs, uint8_t del);
void set_mod_value(Vkvs& vkvs, uint32_t mod_value);
uint8_t get_valid(Vkvs& vkvs);
uint32_t get_value(Vkvs& vkvs);
