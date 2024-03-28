module top (
    input  logic clk,

    //Insert interface
    input  logic insert_p,
    output logic busy_p,
    input  logic ins_key_p,
    input  logic ins_value_p,

    //Lookup/modify interface
    input  logic lookup_p,
    input  logic key_p,
    input  logic modify_p,
    input  logic del_p,
    input  logic mod_value_p,
    output logic valid_p,
    output logic value_p
);

localparam int KEY_BITS = 64;
localparam int VAL_BITS = 64;

(* DONT_TOUCH = "true" *) logic insert;
(* DONT_TOUCH = "true" *) logic busy;
(* DONT_TOUCH = "true" *) logic lookup;
(* DONT_TOUCH = "true" *) logic modify;
(* DONT_TOUCH = "true" *) logic del;
(* DONT_TOUCH = "true" *) logic valid;

(* DONT_TOUCH = "true" *) logic [KEY_BITS-1:0] ins_key;
(* DONT_TOUCH = "true" *) logic [VAL_BITS-1:0] ins_value;
(* DONT_TOUCH = "true" *) logic [KEY_BITS-1:0] key;
(* DONT_TOUCH = "true" *) logic [VAL_BITS-1:0] mod_value;

(* DONT_TOUCH = "true" *) logic [VAL_BITS-1:0] value;
(* DONT_TOUCH = "true" *) logic [VAL_BITS-1:0] value_reg;
(* DONT_TOUCH = "true" *) logic [VAL_BITS-1:0] value_shift;

//Shift in/out the hashtable inputs/outputs since we don't have enough pins
//for all of them
always_ff @(posedge clk) begin
    ins_key   <= {ins_key[KEY_BITS-2:0],   ins_key_p};
    ins_value <= {ins_value[KEY_BITS-2:0], ins_value_p};

    key       <= {key[KEY_BITS-2:0],       key_p};
    mod_value <= {mod_value[VAL_BITS-2:0], mod_value_p};

    value_reg <= value;

    if (valid)
        value_shift <= value_reg;
    else 
        value_shift <= {value_shift[VAL_BITS-2:0], 1'b0};

    insert  <= insert_p;
    busy_p  <= busy;
    lookup  <= lookup_p;
    modify  <= modify_p;
    del     <= del_p;
    valid_p <= valid;

end

assign value_p = value_shift[VAL_BITS-1];

kvs #(
    .NUM_TABLES(4),
    .NUM_ADDR_BITS(12),
    .NUM_KEY_BITS(KEY_BITS),
    .NUM_VAL_BITS(VAL_BITS),
    .NUM_PIPES(2),
    .EN_INS_SEL(0)
) kvs_inst (
    .*
);

endmodule
