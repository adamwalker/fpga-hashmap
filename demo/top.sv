module top (
    input  logic sys_clk_p,
    input  logic sys_clk_n
);

//Clocking
logic sys_clk_gt;
logic sys_clk_i;
logic clk;

IBUFDS_GTE4 pcie_refclk_ibuf
(
    .O(sys_clk_gt),
    .ODIV2(sys_clk_i),
    .I(sys_clk_p),
    .CEB(1'b0),
    .IB(sys_clk_n)
);

BUFG_GT bufg_gt_sysclk_inst (
    .CE      (1'b1),
    .CEMASK  (1'b1),
    .CLR     (1'b0),
    .CLRMASK (1'b1),
    .DIV     (3'b000),
    .I       (sys_clk_i),
    .O       (clk)
);

localparam int KEY_BITS = 64;
localparam int VAL_BITS = 64;

//Insert interface
(* mark_debug *) logic                insert;
(* mark_debug *) logic                busy;
(* mark_debug *) logic [KEY_BITS-1:0] ins_key;
(* mark_debug *) logic [VAL_BITS-1:0] ins_value;

//Lookup/modify interface
(* mark_debug *) logic                lookup;
(* mark_debug *) logic [KEY_BITS-1:0] key;
(* mark_debug *) logic                modify;
(* mark_debug *) logic                del;
(* mark_debug *) logic [VAL_BITS-1:0] mod_value;
(* mark_debug *) logic                valid;
(* mark_debug *) logic [VAL_BITS-1:0] value;

logic insert_p;
logic lookup_p;

vio_0 vio_0_inst (
    .clk(clk),

    .probe_out0(insert_p),
    .probe_out1(lookup_p),
    .probe_out2(modify),
    .probe_out3(del),
    .probe_out4(ins_key),
    .probe_out5(ins_value)
);

logic insert_d;
logic lookup_d;

always_ff @(posedge clk) begin
    insert_d <= insert_p;
    lookup_d <= lookup_p;

    insert <= insert_p && !insert_d;
    lookup <= lookup_p && !lookup_d;
end

assign key       = ins_key;
assign mod_value = ins_value;

hashmap #(
    .NUM_TABLES(4),
    .NUM_ADDR_BITS(12),
    .NUM_KEY_BITS(KEY_BITS),
    .NUM_VAL_BITS(VAL_BITS),
    .NUM_PIPES(2),
    .EN_INS_SEL(1)
) hashmap_inst (
    .*
);

endmodule
