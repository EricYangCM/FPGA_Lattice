module EdgeDetector (
    input  wire clk,
    input  wire rst_n,

    input  wire signal_in,        // 감지할 입력 신호
    input  wire edge_type,        // 1: Rising edge, 0: Falling edge

    output reg edge_pulse         // 엣지 감지되면 1클럭 동안 1 출력
);

    reg signal_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            signal_prev <= 1'b0;
            edge_pulse  <= 1'b0;
        end else begin
            signal_prev <= signal_in;

            if (edge_type) begin
                edge_pulse <= (signal_in == 1'b1 && signal_prev == 1'b0); // rising edge
            end else begin
                edge_pulse <= (signal_in == 1'b0 && signal_prev == 1'b1); // falling edge
            end
        end
    end

endmodule
