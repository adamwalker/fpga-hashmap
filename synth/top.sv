module top #(
    parameter int KEY_BITS = 32,
    parameter int VAL_BITS = 32
)(
    input  logic                clk,

    //Insert interface
    input  logic                insert,
    output logic                busy,
    input  logic [KEY_BITS-1:0] ins_key,
    input  logic [VAL_BITS-1:0] ins_value,

    //Lookup/modify interface
    input  logic                lookup,
    input  logic [KEY_BITS-1:0] key,
    input  logic                modify,    //Asserted the cycle after the lookup
    input  logic                del,
    input  logic [VAL_BITS-1:0] mod_value, //Set the cycle after the lookup
    output logic                valid,
    output logic [VAL_BITS-1:0] value
);

kvs #(
    .NUM_TABLES(4),
    .NUM_ADDR_BITS(12),
    .NUM_KEY_BITS(KEY_BITS),
    .NUM_VAL_BITS(VAL_BITS),
    .NUM_PIPES(2),
    .EN_INS_SEL(1)
) kvs_inst (
    .*
);

endmodule
