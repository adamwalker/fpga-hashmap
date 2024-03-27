//RAM module with a configurable read pipeline depth
module ram #(
    parameter int ADDR_WIDTH = 4,
    parameter int DATA_WIDTH = 8,
    parameter int NUM_PIPES  = 0
) (
    input  logic                  clk,

    input  logic                  write_en,
    input  logic [ADDR_WIDTH-1:0] write_addr,
    input  logic [ADDR_WIDTH-1:0] read_addr,
    input  logic [DATA_WIDTH-1:0] write_val,
    output logic [DATA_WIDTH-1:0] read_val
);

logic [DATA_WIDTH-1:0] values[2**ADDR_WIDTH];

initial
    for (int i=0; i<2**ADDR_WIDTH; i++)
        values[i] = 'h0;

logic [DATA_WIDTH-1:0] read_val_p[NUM_PIPES+1];

initial
    for(int i=0; i<NUM_PIPES+1; i++)
        read_val_p[i] = 'h0;

assign read_val = read_val_p[NUM_PIPES];

always_ff @(posedge clk) begin

    if (write_en)
        values[write_addr] <= write_val;

    read_val_p[0] <= values[read_addr];

    for(int i=1; i<NUM_PIPES+1; i++)
        read_val_p[i] <= read_val_p[i-1];
end

endmodule
