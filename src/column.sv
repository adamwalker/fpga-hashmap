module column #(
    parameter int NUM_KEY_BITS  = 8,
    parameter int NUM_VAL_BITS  = 8,
    parameter int NUM_ADDR_BITS = 4,
    parameter int NUM_PIPES     = 1
)(
    input  logic                     clk,

`ifdef FORMAL
    input  logic [NUM_KEY_BITS-1:0]  f_key,
`endif

    //Insert interface
    output logic                     busy,      //We can accept an insert on the eviction input this cycle

    //Lookup interface
    input  logic                     lookup,    //Set to suspend any active inserts for one cycle and initiate a lookup
    input  logic [NUM_KEY_BITS-1:0]  lu_key,    //Key to lookup
    input  logic                     modify,    //Set NUM_PIPES cycles after the lookup
    input  logic                     del,       //Set NUM_PIPES cycles after the lookup
    input  logic [NUM_VAL_BITS-1:0]  mod_value, //Set NUM_PIPES cycles after the lookup
    output logic                     lu_valid,  //Output NUM_PIPES cycles after the lookup
    output logic [NUM_VAL_BITS-1:0]  lu_value,  //Output NUM_PIPES cycles after the lookup

    //Hasher
    output logic [NUM_KEY_BITS-1:0]  hash_key,
    input  logic [NUM_ADDR_BITS-1:0] hash,      //Must be a combinational function of hash_key

    //Cuckoo loop
    input  logic                     match_in,
    //Eviction/insert input
    input  logic                     ev_in_valid,
    input  logic [NUM_KEY_BITS-1:0]  ev_key_in,
    input  logic [NUM_VAL_BITS-1:0]  ev_value_in,
    //Eviction output
    output logic                     ev_out_valid,
    output logic [NUM_KEY_BITS-1:0]  ev_key_out,
    output logic [NUM_VAL_BITS-1:0]  ev_value_out
);

/*
 * RAMs
 */
logic [NUM_ADDR_BITS-1:0] read_addr;
logic [NUM_ADDR_BITS-1:0] write_addr;
logic [NUM_ADDR_BITS-1:0] addr_pipe[NUM_PIPES];

logic                     write_en_key;
logic                     write_en_value;

logic                     write_valid;
logic [NUM_KEY_BITS-1:0]  write_key;
logic [NUM_VAL_BITS-1:0]  write_val;

logic                     read_valid;
logic [NUM_KEY_BITS-1:0]  read_key;
logic [NUM_VAL_BITS-1:0]  read_value;

assign write_addr = addr_pipe[NUM_PIPES-1];

ram #(
    .ADDR_WIDTH(NUM_ADDR_BITS),
    .DATA_WIDTH(1),
    .NUM_PIPES(NUM_PIPES-1)
) ram_en_inst (
    .clk(clk),
    .write_en(write_en_value),
    .write_addr(write_addr),
    .read_addr(read_addr),
    .write_val(write_valid),
    .read_val(read_valid)
);

ram #(
    .ADDR_WIDTH(NUM_ADDR_BITS),
    .DATA_WIDTH(NUM_KEY_BITS),
    .NUM_PIPES(NUM_PIPES-1)
) ram_key_inst (
    .clk(clk),
    .write_en(write_en_key),
    .write_addr(write_addr),
    .read_addr(read_addr),
    .write_val(write_key),
    .read_val(read_key)
);

ram #(
    .ADDR_WIDTH(NUM_ADDR_BITS),
    .DATA_WIDTH(NUM_VAL_BITS),
    .NUM_PIPES(NUM_PIPES-1)
) ram_value_inst (
    .clk(clk),
    .write_en(write_en_value),
    .write_addr(write_addr),
    .read_addr(read_addr),
    .write_val(write_val),
    .read_val(read_value)
);

/*
 * Lookup saved state
 */
logic                    lookup_q[NUM_PIPES];
logic [NUM_KEY_BITS-1:0] lu_key_q[NUM_PIPES];

initial
    for(int i=0; i<NUM_PIPES; i++)
        lookup_q[i] = 1'b0;

always_ff @(posedge clk) begin

    lookup_q[0] <= lookup;
    lu_key_q[0] <= lu_key;

    for(int i=1; i<NUM_PIPES; i++) begin
        lookup_q[i] <= lookup_q[i-1];
        lu_key_q[i] <= lu_key_q[i-1];
    end

end

/*
 * Delayed eviction
 */
logic                    delayed_ev_valid[NUM_PIPES];
logic [NUM_KEY_BITS-1:0] delayed_ev_key[NUM_PIPES];
logic [NUM_VAL_BITS-1:0] delayed_ev_value[NUM_PIPES];

initial
    for(int i=0; i<NUM_PIPES; i++)
        delayed_ev_valid[i] = 1'b0;

/*
 * Eviction forwarding
 */
logic forward_conflict_value[NUM_PIPES];
logic forward_conflict_key[NUM_PIPES];

initial
    for(int i=0; i<NUM_PIPES; i++) begin
        forward_conflict_value[i] = 1'b0;
        forward_conflict_key[i]   = 1'b0;
    end

logic                    forward_valid[NUM_PIPES];
logic [NUM_VAL_BITS-1:0] forward_value[NUM_PIPES];
logic [NUM_KEY_BITS-1:0] forward_key[NUM_PIPES];

/*
 * Match forwarding
 */
logic                    forward_match[NUM_PIPES];
logic [NUM_VAL_BITS-1:0] forward_value_lookup[NUM_PIPES];
initial
    for(int i=0; i<NUM_PIPES; i++)
        forward_match[i] = 1'b0;

/*
 * Modification forwarding
 */
logic                    forward_match_mod[NUM_PIPES];
logic                    forward_invalidate_mod[NUM_PIPES];

logic                    do_overwrite;

always_ff @(posedge clk) begin
    /*
     * RAM read/write conflicts
     * These signals are only used for evictions. 
     * There are two cases:
     *     * !lookup_q => Possible incoming eviction 
     *                    No buffered eviction or modify operation possible
     *                    Forward enable, value, key from delayed eviction, if addresses conflict
     *                    And combine with incoming enable
     *     *  lookup_q => No possible incoming eviction
     *                    Reading from delayed eviction slot
     *                    Forward enable, value, but not key, since modifications dont change the key
     *                    And combine with incoming enable
     */
    forward_conflict_value[0] <= write_en_value && (read_addr == write_addr);
    forward_valid[0]          <= write_valid;
    forward_value[0]          <= write_val;

    forward_conflict_key[0]   <= write_en_key && (read_addr == write_addr);
    forward_key[0]            <= write_key;

    for (int i=1; i<NUM_PIPES; i++) begin

        if(write_en_value && addr_pipe[i-1] == write_addr) begin

            forward_conflict_value[i] <= 1'b1;
            forward_valid[i]          <= write_valid;
            forward_value[i]          <= write_val;

        end else begin

            forward_conflict_value[i] <= forward_conflict_value[i-1];
            forward_valid[i]          <= forward_valid[i-1];
            forward_value[i]          <= forward_value[i-1];
                                                                  
        end

        if(write_en_key && addr_pipe[i-1] == write_addr) begin

            forward_conflict_key[i]   <= 1'b1;
            forward_key[i]            <= write_key;

        end else begin

            forward_conflict_key[i]   <= forward_conflict_key[i-1];
            forward_key[i]            <= forward_key[i-1];

        end

    end

    /*
     * Lookup doesn't need to forward around the ram, because it is guaranteed
     * that an evicted value is only overwritten NUM_PIPES cycles later and
     * therefore will still be in the ram. However, we do need to check the
     * delayed eviction value for a match.
     */
    forward_match[0] <= 1'b0;
    for (int i=0; i<NUM_PIPES; i++)
        if (delayed_ev_valid[i] && delayed_ev_key[i] == lu_key) begin
            forward_match[0]          <= 1'b1;
            forward_value_lookup[0]   <= delayed_ev_value[i];
        end

    //Match delay to RAM
    for (int i=1; i<NUM_PIPES; i++) begin
        forward_match[i]        <= forward_match[i-1];
        forward_value_lookup[i] <= forward_value_lookup[i-1];
    end

    /*
     * RAM state detection for modifications
     *
     * Like for inserts, we have a match signal that flags a match with the key in the delay buffer. 
     * This is additionally qualified by !lookup_q since that is the case when we are actually writing the
     * delayed eviction to RAM, and thus will need to be overwritten on the
     * writeback cycle
     * 
     * Additionally, we invalidate matches. Again, there are two cases:
     *     * !lookup_q => We are writing the delayed eviction. If we did have
     *                    a match in RAM, we certainly won't after the
     *                    eviction is written, since a key can only live in one 
     *                    location. 
     *     *  lookup_q => We are possibly doing a writeback. Invalidate if we
     *                    are doing a writeback and it's a delete.
     */
    forward_match_mod[0] 
        <= delayed_ev_key[NUM_PIPES-1] == lu_key
        && !lookup_q[NUM_PIPES-1] && delayed_ev_valid[NUM_PIPES-1];

    for (int i=1; i<NUM_PIPES; i++)
        if((lookup_q[NUM_PIPES-1] ? 1'b0 : delayed_ev_valid[NUM_PIPES-1]) && lu_key_q[i-1] == delayed_ev_key[NUM_PIPES-1])
            forward_match_mod[i] <= 1'b1;
        else
            forward_match_mod[i] 
                <= forward_match_mod[i-1] 
                && !((lookup_q[NUM_PIPES-1] ? (do_overwrite && modify && del) : delayed_ev_valid[NUM_PIPES-1]) && addr_pipe[i-1] == write_addr);

    forward_invalidate_mod[0] 
        <= write_addr == read_addr
        && (lookup_q[NUM_PIPES-1] ? (do_overwrite && modify && del) : delayed_ev_valid[NUM_PIPES-1]);

    for (int i=1; i<NUM_PIPES; i++)
        if((lookup_q[NUM_PIPES-1] ? (do_overwrite && modify && del) : delayed_ev_valid[NUM_PIPES-1]) && addr_pipe[i-1] == write_addr)
            forward_invalidate_mod[i] <= 1'b1;
        else
            forward_invalidate_mod[i] <= forward_invalidate_mod[i-1];
end

/*
 * Delayed eviction buffer
 */
assign busy = delayed_ev_valid[NUM_PIPES-1] && lookup_q[NUM_PIPES-1];

always_ff @(posedge clk) begin
    if (!busy) begin
        delayed_ev_valid[0] <= ev_in_valid;
        delayed_ev_key[0]   <= ev_key_in;
        delayed_ev_value[0] <= ev_value_in;
    end else begin

        //Key never changes on modify or delete operations
        delayed_ev_key[0] <= delayed_ev_key[NUM_PIPES-1];

        //Value and enable can change due to reset and modify operations
        //We check match because we need to be sure that the key was in the hashtable at the time of lookup
        if (match_in && modify && delayed_ev_key[NUM_PIPES-1] == lu_key_q[NUM_PIPES-1]) begin
            delayed_ev_valid[0] <= !del;
            delayed_ev_value[0] <= mod_value;
        end else begin
            delayed_ev_valid[0] <= delayed_ev_valid[NUM_PIPES-1];
            delayed_ev_value[0] <= delayed_ev_value[NUM_PIPES-1];
        end
    end

    for(int i=1; i<NUM_PIPES; i++) begin
        //Key never changes on modify or delete operations
        delayed_ev_key[i]   <= delayed_ev_key[i-1];

        //Value and enable can change due to reset and modify operations
        //We check match because we need to be sure that the key was in the hashtable at the time of lookup
        if (match_in && modify && delayed_ev_key[i-1] == lu_key_q[NUM_PIPES-1]) begin
            delayed_ev_valid[i] <= delayed_ev_valid[i-1] && !del;
            delayed_ev_value[i] <= mod_value;
        end else begin
            delayed_ev_valid[i] <= delayed_ev_valid[i-1];
            delayed_ev_value[i] <= delayed_ev_value[i-1];
        end
    end

end

/*
 * RAM Enables
 */
assign write_en_key   = lookup_q[NUM_PIPES-1] ? 1'b0                     : delayed_ev_valid[NUM_PIPES-1];
assign write_en_value = lookup_q[NUM_PIPES-1] ? (modify && do_overwrite) : delayed_ev_valid[NUM_PIPES-1];

/*
 * RAM Values
 */
assign write_valid    = lookup_q[NUM_PIPES-1] ? !del      : 1'b1;
assign write_key      = delayed_ev_key[NUM_PIPES-1];
assign write_val      = lookup_q[NUM_PIPES-1] ? mod_value : delayed_ev_value[NUM_PIPES-1];

/*
 * Outgoing evictions
 */
logic eviction_happening;
assign eviction_happening = !lookup_q[NUM_PIPES-1] && delayed_ev_valid[NUM_PIPES-1];

assign ev_out_valid = eviction_happening && (forward_conflict_value[NUM_PIPES-1] ? forward_valid[NUM_PIPES-1] : read_valid);
assign ev_key_out   =                        forward_conflict_key[NUM_PIPES-1]   ? forward_key[NUM_PIPES-1]   : read_key;
assign ev_value_out =                        forward_conflict_value[NUM_PIPES-1] ? forward_value[NUM_PIPES-1] : read_value;

/*
 * Lookup matching
 */
logic  ram_match;
assign ram_match = read_valid && (lu_key_q[NUM_PIPES-1] == read_key);

assign lu_valid 
    =  lookup_q[NUM_PIPES-1] 
    && (forward_match[NUM_PIPES-1] || ram_match);
assign lu_value = forward_match[NUM_PIPES-1] ? forward_value_lookup[NUM_PIPES-1] : read_value;

`ifdef FORMAL
//We can't have both a RAM and a bypass match
always_comb 
    if (lu_key_q[NUM_PIPES-1] == f_key)
        assert(!(forward_match[NUM_PIPES-1] && ram_match));
`endif

/*
 * Hash selection and address calculation
 * Idea is to instantiate the hash calculation logic only once per table.
 */
always_comb 
    if (lookup)
        hash_key = lu_key;
    else if (busy)
        hash_key = delayed_ev_key[NUM_PIPES-1];
    else
        hash_key = ev_key_in;

assign read_addr = hash;

always_ff @(posedge clk) begin
    addr_pipe[0] <= read_addr;
    for(int i=1; i<NUM_PIPES; i++)
        addr_pipe[i] <= addr_pipe[i-1];
end

/*
 * Modifications
 */
assign do_overwrite 
    = forward_match_mod[NUM_PIPES-1] || (ram_match && !forward_invalidate_mod[NUM_PIPES-1]);

endmodule
