#include <sim/src/lib.hpp>
#include <sim/src/main.rs.h>

std::unique_ptr<VerilatedContext> new_context_unique() {
    return std::make_unique<VerilatedContext>();
}

std::unique_ptr<Vhashmap> new_vhashmap_unique(VerilatedContext& context) {
    return std::make_unique<Vhashmap>(&context);
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

void set_clk(Vhashmap& vhashmap, uint8_t clk) {
    vhashmap.clk = clk;
}

void set_insert(Vhashmap& vhashmap, uint8_t insert) {
    vhashmap.insert = insert;
}

uint8_t get_busy(Vhashmap& vhashmap) {
    return vhashmap.busy;
}

void set_ins_key(Vhashmap& vhashmap, uint32_t ins_key) {
    vhashmap.ins_key = ins_key;
}

void set_ins_value(Vhashmap& vhashmap, uint32_t ins_value) {
    vhashmap.ins_value = ins_value;
}

void set_lookup(Vhashmap& vhashmap, uint8_t lookup) {
    vhashmap.lookup = lookup;
}

void set_key(Vhashmap& vhashmap, uint32_t key) {
    vhashmap.key = key;
}

void set_modify(Vhashmap& vhashmap, uint8_t modify) {
    vhashmap.modify = modify;
}

void set_del(Vhashmap& vhashmap, uint8_t del) {
    vhashmap.del = del;
}

void set_mod_value(Vhashmap& vhashmap, uint32_t mod_value) {
    vhashmap.mod_value = mod_value;
}

uint8_t get_valid(Vhashmap& vhashmap) {
    return vhashmap.valid;
}

uint32_t get_value(Vhashmap& vhashmap) {
    return vhashmap.value;
}
