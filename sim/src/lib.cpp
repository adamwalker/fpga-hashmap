#include <sim/src/lib.hpp>
#include <sim/src/main.rs.h>

std::unique_ptr<VerilatedContext> new_context_unique() {
    return std::make_unique<VerilatedContext>();
}

std::unique_ptr<Vkvs> new_vkvs_unique(VerilatedContext& context) {
    return std::make_unique<Vkvs>(&context);
}

std::unique_ptr<VerilatedFstC> new_fstc_unique() {
    return std::make_unique<VerilatedFstC>();
}

void trace_ever_on(bool on) {
    Verilated::traceEverOn(on);
}

/*
 * IO
 */

void set_clk(Vkvs& vkvs, uint8_t clk) {
    vkvs.clk = clk;
}

void set_insert(Vkvs& vkvs, uint8_t insert) {
    vkvs.insert = insert;
}

uint8_t get_busy(Vkvs& vkvs) {
    return vkvs.busy;
}

void set_ins_key(Vkvs& vkvs, uint32_t ins_key) {
    vkvs.ins_key = ins_key;
}

void set_ins_value(Vkvs& vkvs, uint32_t ins_value) {
    vkvs.ins_value = ins_value;
}

void set_lookup(Vkvs& vkvs, uint8_t lookup) {
    vkvs.lookup = lookup;
}

void set_key(Vkvs& vkvs, uint32_t key) {
    vkvs.key = key;
}

void set_modify(Vkvs& vkvs, uint8_t modify) {
    vkvs.modify = modify;
}

void set_del(Vkvs& vkvs, uint8_t del) {
    vkvs.del = del;
}

void set_mod_value(Vkvs& vkvs, uint32_t mod_value) {
    vkvs.mod_value = mod_value;
}

uint8_t get_valid(Vkvs& vkvs) {
    return vkvs.valid;
}

uint32_t get_value(Vkvs& vkvs) {
    return vkvs.value;
}
