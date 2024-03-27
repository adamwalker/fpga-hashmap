/*
 * An FPGA-based hashtable
 *
 * Its operation is specified below, but for the ultimate unambiguous
 * specification, see formal.sv in the formal directory.
 *
 * Inserts may be initiated any time the busy signal is not asserted. Once
 * inserted, the key/value pair is considered to be in the hashtable on the
 * next cycle and lookups initiated in that cycle will succeed. Under the hood,
 * the insert operation takes a variable amount of time, but values are
 * forwarded so that the key/value pair appears to be immediately available
 * for lookups, modifications and deletes.
 *
 * It is illegal to insert a key that is already inserted. If it is possible
 * that a key already exists in the hashtable, perform a lookup, followed by
 * a modify or insert operation depending on whether they key was present.
 *
 * Lookups return the value that was in the hashtable on the clock cycle when
 * the lookup request was made. If a lookup and an insert to the same key take
 * place in the same cycle, then the insert is considered to have happened
 * first. The lookup result is made available to the user NUM_PIPES cycles
 * later.
 *
 * Modify/delete operations are always preceded by a lookup operation
 * NUM_PIPES cycles in advance to find the location of the value to modify. 
 *
 * While modifications and deletes are accepted two cycles after the initial
 * lookup, they are are forwarded to subsequent lookups so that they appear to
 * have taken effect by the cycle after the initial lookup took place. This is
 * to enable back to back read-modify-write operations on a single key.
 */
module kvs #(
    parameter int NUM_TABLES    = 4,  //Maximum of 4 tables supported
    parameter int NUM_ADDR_BITS = 12,
    parameter int NUM_KEY_BITS  = 32,
    parameter int NUM_VAL_BITS  = 32,
    parameter int NUM_PIPES     = 2,  //Must be at least 1
    parameter int EN_INS_SEL    = 1   //See comment below where this parameter is used
)(
    input  logic                    clk,

`ifdef FORMAL
    input  logic [NUM_KEY_BITS-1:0] f_key,
`endif

    //Insert interface
    input  logic                    insert,    //Initiate an insert on this cycle
    output logic                    busy,      //We can accept an insert on this cycle
    input  logic [NUM_KEY_BITS-1:0] ins_key,   //Key to insert
    input  logic [NUM_VAL_BITS-1:0] ins_value, //Value to insert

    //Lookup/modify interface
    input  logic                    lookup,    //Assert to suspend any active inserts for one cycle and initiate a lookup
    input  logic [NUM_KEY_BITS-1:0] key,       //Key to lookup
    input  logic                    modify,    //Asserted NUM_PIPES cycles after the lookup to modify/delete the looked-up entry
    input  logic                    del,       //Asserted NUM_PIPES cycles after the lookup to delete the entry
    input  logic [NUM_VAL_BITS-1:0] mod_value, //Set NUM_PIPES cycles after the lookup. New value for modify operation.
    //Lookup result
    output logic                    valid,     //Output NUM_PIPES cycles after the lookup
    output logic [NUM_VAL_BITS-1:0] value      //Output NUM_PIPES cycles after the lookup
);

logic                    lu_valid[NUM_TABLES];
logic [NUM_VAL_BITS-1:0] lu_value[NUM_TABLES];
logic                    busys[NUM_TABLES];

/*
 * Keep forwarding tables of modifications/deletions with their preceding
 * lookups and keys. These are used in the lookup logic in the next always
 * block.
 */
logic                    lookup_q[NUM_PIPES];
logic                    del_q[NUM_PIPES];
logic [NUM_KEY_BITS-1:0] key_q[NUM_PIPES];
logic [NUM_VAL_BITS-1:0] mod_value_q[NUM_PIPES];
logic                    forward_modify[NUM_PIPES];

initial 
    for(int i=0; i<NUM_PIPES; i++)
        lookup_q[i] = 1'b0;

always_ff @(posedge clk) begin

    key_q[0]    <= key;
    lookup_q[0] <= lookup;

    for(int i=1; i<NUM_PIPES; i++) begin
        key_q[i]    <= key_q[i-1];
        lookup_q[i] <= lookup_q[i-1];
    end

    del_q[0]          <= 1'b0; 
    forward_modify[0] <= 1'b0;

    if (key_q[NUM_PIPES-1] == key && lookup_q[NUM_PIPES-1] && modify && valid) begin
        del_q[0]          <= del; 
        mod_value_q[0]    <= mod_value;
        forward_modify[0] <= 1'b1;
    end

    for(int i=1; i<NUM_PIPES; i++) begin
        if (key_q[NUM_PIPES-1] == key_q[i-1] && lookup_q[NUM_PIPES-1] && modify && valid) begin
            del_q[i]          <= del_q[i-1] || del; 
            mod_value_q[i]    <= mod_value;
            forward_modify[i] <= 1'b1;
        end else begin
            del_q[i]          <= del_q[i-1]; 
            mod_value_q[i]    <= mod_value_q[i-1];
            forward_modify[i] <= forward_modify[i-1];
        end
    end
end

//Lookup logic with corrections from the forwarding storage above
always_comb begin
    valid = 1'b0;
    value = 'h0;

    for(int i=0; i<NUM_TABLES; i++)
        if (lu_valid[i]) begin
`ifdef FORMAL
            /*
             * At most one table should return valid, because it is an invariant
             * that the key/value will be stored in at most one table.
             */
            if (key_q[NUM_PIPES-1] == f_key)
                assert(!valid);
`endif
            
            /*
             * Only forward if the (possibly stale) key was actually found in
             * a table. This prevents the case where we forward a modification
             * present in the forwarding tables above, but it was never actually
             * inserted.
             */
            if (forward_modify[NUM_PIPES-1]) begin
                value = mod_value_q[NUM_PIPES-1];
                valid = !del_q[NUM_PIPES-1];
            end else begin
                value = lu_value[i];
                valid = 1'b1;
            end
        end
end

//Evictions
logic                    ev_valid_in[NUM_TABLES];
logic [NUM_KEY_BITS-1:0] ev_key_in[NUM_TABLES];
logic [NUM_VAL_BITS-1:0] ev_value_in[NUM_TABLES];

logic                    ev_valid_out[NUM_TABLES];
logic [NUM_KEY_BITS-1:0] ev_key_out[NUM_TABLES];
logic [NUM_VAL_BITS-1:0] ev_value_out[NUM_TABLES];

//Inject insertions
if (EN_INS_SEL == 1) begin: gen_insert_sel

    //Inject inserts into any table that isn't currently busy
    //Performs slightly better on insertion heavy workloads at the cost of
    //complexity and logic depth

    logic masked[NUM_TABLES];
    logic masked_accum[NUM_TABLES];
    always_comb begin

        masked[0]       = busys[0] || ev_valid_out[NUM_TABLES-1];
        masked_accum[0] = masked[0];

        for(int i=1; i<NUM_TABLES; i++) begin
            masked[i]       = (busys[i] || ev_valid_out[i-1]);
            masked_accum[i] = masked[i] && masked_accum[i-1];
        end
    end

    assign busy = masked_accum[NUM_TABLES-1];

    always_comb
        if (!masked[0]) begin
            ev_valid_in[0] = insert;
            ev_key_in[0]   = ins_key;
            ev_value_in[0] = ins_value;
        end else begin
            ev_valid_in[0] = ev_valid_out[NUM_TABLES-1];
            ev_key_in[0]   = ev_key_out[NUM_TABLES-1];
            ev_value_in[0] = ev_value_out[NUM_TABLES-1];
        end

    always_comb begin

        for (int i=1; i<NUM_TABLES; i++) begin
            if (!masked[i]) begin
                ev_valid_in[i] = insert && masked_accum[i-1];
                ev_key_in[i]   = ins_key;
                ev_value_in[i] = ins_value;
            end else begin
                ev_valid_in[i] = ev_valid_out[i-1];
                ev_key_in[i]   = ev_key_out[i-1];
                ev_value_in[i] = ev_value_out[i-1];
            end
        end

    end

end else begin: gen_simple_insert

    //Only inject inserts into the first table
    //Simplifies the logic at the expense of performance on insert-heavy
    //workloads

    assign busy = ev_valid_out[NUM_TABLES-1] || busys[0];

    always_comb
        if (!busy) begin
            ev_valid_in[0] = insert;
            ev_key_in[0]   = ins_key;
            ev_value_in[0] = ins_value;
        end else begin
            ev_valid_in[0] = ev_valid_out[NUM_TABLES-1];
            ev_key_in[0]   = ev_key_out[NUM_TABLES-1];
            ev_value_in[0] = ev_value_out[NUM_TABLES-1];
        end

    //Create the eviction loop
    for (genvar i=1; i<NUM_TABLES; i++) begin: evict_plumb
        always_comb begin
            ev_valid_in[i] = ev_valid_out[i-1];
            ev_key_in[i]   = ev_key_out[i-1];
            ev_value_in[i] = ev_value_out[i-1];
        end
    end

end

//Tables
for (genvar i=0; i<NUM_TABLES; i++) begin: cuckoo_loop

    logic [NUM_KEY_BITS-1:0]  hash_key;
    logic [NUM_ADDR_BITS-1:0] hash;

    column #(
        .NUM_KEY_BITS(NUM_KEY_BITS),
        .NUM_VAL_BITS(NUM_VAL_BITS),
        .NUM_ADDR_BITS(NUM_ADDR_BITS),
        .NUM_PIPES(NUM_PIPES)
    ) column_inst (
        .clk(clk),
        //Formal
`ifdef FORMAL
        .f_key(f_key),
`endif
        //Inserts
        .busy(busys[i]),
        //Lookups
        .lookup(lookup),
        .modify(modify),
        .del(del),
        .lu_key(key),
        .mod_value(mod_value),
        .lu_valid(lu_valid[i]),
        .lu_value(lu_value[i]),
        .hash_key(hash_key),
        .hash(hash),
        //Optimise: match_in only needs to know about matches from the current
        //and previous table in the loop. 
        //That would have better locality.
        .match_in(valid),
        //Evictions and inserts in
        .ev_in_valid(ev_valid_in[i]),
        .ev_key_in(ev_key_in[i]),
        .ev_value_in(ev_value_in[i]),
        //Evictions out
        .ev_out_valid(ev_valid_out[i]),
        .ev_key_out(ev_key_out[i]),
        .ev_value_out(ev_value_out[i])
    );

`ifdef FORMAL
    //YOSYS open source edition cannot parse the CRC module, so use a dummy
    //hash function that just passes different bits of the key through.

    //Bounded model checking has also been performed successfully with
    //a hacked together version of the CRC below that YOSYS is able to parse,
    //though it's slower, and makes this code a mess, so is not included here.

    //Ideally, we'd use uninterpreted functions, but I don't believe
    //YOSYS supports them. TODO: investigate this, since the bounded model
    //check isn't really valid otherwise.

    assign hash = hash_key[i*4 +: 4];

`else
    //CRC hashes for up to four tables. Four tables allow 95%+ load factors,
    //so this should be enough for most purposes.
    //CRCs are used because the are very efficient in hardware and seem to
    //work well as hash functions.
    //Ideally, these polynomials would be passed in as parameters, but
    //limitations of the open source YOSYS SystemVerilog parser prevent this.

    localparam logic[31:0] POLYS[4] = '{
        32'h04c11db7,
        32'h1edc6f41,
        32'h741b8cd7,
        32'h32583499
    };

    logic [31:0] crc_out;

    crc #(
        .POLY_SIZE(32),
        .POLY(POLYS[i]),
        .DATA_WIDTH(NUM_KEY_BITS)
    ) crc_inst (
        .data_in(hash_key),
        .crc_out(crc_out)
    );

    assign hash = crc_out[NUM_ADDR_BITS-1:0];
`endif

end

endmodule
