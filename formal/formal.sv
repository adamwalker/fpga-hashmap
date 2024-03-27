module formal #(
    parameter int NUM_KEY_BITS  = 8,
    parameter int NUM_VAL_BITS  = 8,
    parameter int NUM_PIPES     = 2,
    parameter int NUM_TABLES    = 2,
    parameter int NUM_ADDR_BITS = 4
)(
    input logic                    clk,

    //The SMT solver is free to set these signals almost however it wants.
    //The only restriction is that the single assume statement below holds.
    input logic                    insert,
    input logic [NUM_KEY_BITS-1:0] ins_key,
    input logic [NUM_VAL_BITS-1:0] ins_value,

    input logic                    lookup,
    input logic [NUM_KEY_BITS-1:0] key,
    input logic                    modify,
    input logic                    del,
    input logic [NUM_VAL_BITS-1:0] mod_value
);

/*
 * Uses the trick described here: https://zipcpu.com/zipcpu/2018/07/13/memories.html
 * In summary, it is sufficient to pick a single key and verify that
 * operations on just that key return the correct value
 */
(* anyconst *) logic [NUM_KEY_BITS-1:0] f_key;

//Instantiate the design under test
logic                    valid;
logic                    busy;
logic [NUM_VAL_BITS-1:0] value;

kvs #(
    .NUM_TABLES(NUM_TABLES),
    .NUM_ADDR_BITS(NUM_ADDR_BITS),
    .NUM_KEY_BITS(NUM_KEY_BITS),
    .NUM_VAL_BITS(NUM_VAL_BITS),
    .NUM_PIPES(NUM_PIPES),
    .EN_INS_SEL(1)
) kvs_inst (
    .clk(clk),

    //f_key is only used for internal consistency assertions within the design.
    //It is not part of the design when synthesized.
    .f_key(f_key),

    //Insert interface
    //Busy prevents us from inserting but does not block any other operations
    .busy(busy),
    .insert(insert),
    .ins_key(ins_key),
    .ins_value(ins_value),

    //Lookup/modify/delete interface
    .lookup(lookup),
    .key(key),
    .modify(modify),
    .del(del),
    .mod_value(mod_value),
    .valid(valid),
    .value(value)
);

/*
 * Lookups return the value that was in the hashtable on the clock cycle when
 * the lookup request was made.
 *
 * However, the lookup result is made available to the user NUM_PIPES cycles
 * later.
 *
 * So, we keep a pipeline representing the value associated with f_key on the
 * cycle the lookup was initiated and use that in assertions at the end of
 * this file.
 *
 * We also keep a f_past_lookup pipeline of previous lookup requests so that
 * we know when to check hashtable output assertions. The f_past_lookup
 * pipeline is one item shorter than f_valid and f_value since if a lookup and
 * insert take place in the same cycle, with the same key, the lookup is
 * considered to have taken place before the insert, ie the lookup is a miss.
 */
logic                    f_valid[NUM_PIPES + 1];
logic [NUM_VAL_BITS-1:0] f_value[NUM_PIPES + 1];
logic                    f_past_lookup[NUM_PIPES];

initial begin
    for(int i=0; i<NUM_PIPES; i++) begin
        f_past_lookup[i] = 1'b0;
    end

    for(int i=0; i<NUM_PIPES + 1; i++) begin
        f_valid[i] = 1'b0;
    end
end

always @(posedge clk) begin

    /*
     * Formal insert logic
     * Inserts are only accepted if the hashtable is currently not busy
     */
    if (ins_key == f_key && !busy && insert) begin

        //It is illegal to insert a key that is already inserted
        assume(!f_valid[NUM_PIPES]);

        //Load up the start of the formal pipeline`
        f_valid[NUM_PIPES] <= 1'b1;
        f_value[NUM_PIPES] <= ins_value;
    end 

    /*
     * Formal lookup/modify/delete logic
     * Modify/delete operations are always proceeded by a lookup operation
     * NUM_PIPES cycles in advance to find the location of the value to modify. 
     *
     * While modifications and deletes are accepted two cycles after the
     * initial lookup, they are are forwarded to subsequent lookups so that
     * they appear to have taken effect by the cycle after the initial lookup
     * took place. 
     *
     * This is to enable back to back read-modify-write operations on a single
     * key.
     *
     * Modifications and deletes are therefore mapped backwards in time in the
     * formal pipelines to appear as if they occurred the cycle after the
     * original lookup happened.
     *
     * TODO: This is a bit trippy and complicates the formal model as well as
     * the forwarding logic in the hashtable. Is it actually a good idea?
     */
    for(int i=0; i<NUM_PIPES; i++) begin
        f_valid[i] <= f_valid[i+1];
        f_value[i] <= f_value[i+1];
    end

    if (f_valid[0] && f_past_lookup[0] && modify)
        for(int i=0; i<NUM_PIPES + 1; i++) begin
            f_valid[i] <= !del;
            f_value[i] <= mod_value;
        end

end

/*
 * Formal pipeline of past lookup requests initiated by the formal model that
 * match the key we are tracking. These are used to know when to check the
 * lookup result, ie after the hashtable pipeline delay.
 */
always @(posedge clk) begin
    f_past_lookup[NUM_PIPES-1] <= lookup && key == f_key;

    for(int i=0; i<NUM_PIPES-1; i++)
        f_past_lookup[i] <= f_past_lookup[i+1];
end

/*
 * Check the lookups match the expected value when they reach the end of the
 * pipeline and are outputted by the hashtable
 */
always @(*)
    if (f_past_lookup[0]) begin
        assert (f_valid[0] == valid); //Key presence is correct
        if (f_valid[0])
            assert (f_value[0] == value); //Key value is correct
    end

/*
 * Sanity check that we actually insert anything. The hashtable could satisfy
 * some assertions if, for example, it constantly asserted busy and nothing
 * was ever inserted.
 */
always @(*) begin
    cover(f_past_lookup[0]);
    cover(!busy);
end

endmodule

