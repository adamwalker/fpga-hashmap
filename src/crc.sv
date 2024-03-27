/*
 * A combinational CRC module that is generic in the crc width, input data
 * width, and polynomial.
 *
 * Timing and logic depth: each output bit is an XOR tree function of half of
 * the input bits on average.
 */
module crc #(
    parameter int                   POLY_SIZE  = 32,
    parameter logic [POLY_SIZE-1:0] POLY       = 32'h04c11db7,
    parameter int                   DATA_WIDTH = 32
) (
    input  logic [DATA_WIDTH-1:0] data_in,
    output logic [POLY_SIZE-1:0]  crc_out
);

typedef logic [POLY_SIZE-1:0] lfsr_lut_t [DATA_WIDTH];

function lfsr_lut_t gen_lut();

    lfsr_lut_t lut;
    lut[0] = POLY;

    for(int i=0; i<DATA_WIDTH-1; i++)
       if (lut[i][POLY_SIZE-1])
           lut[i+1] = (lut[i] << 1) ^ POLY;
       else
           lut[i+1] = lut[i] << 1;

    gen_lut = lut;

endfunction

localparam lfsr_lut_t lut = gen_lut();

logic [POLY_SIZE-1:0] result;

always_comb begin
    result = 'h0;
    for(int i=0; i<DATA_WIDTH; i++)
        result = result ^ (lut[i] & {POLY_SIZE{data_in[i]}});
end

assign crc_out = result;

endmodule
