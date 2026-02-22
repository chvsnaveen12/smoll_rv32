module plic_tb;
    logic        clk, rst_n;
    logic        req_valid;
    logic [31:0] req_addr;
    logic [31:0] req_value;
    logic [3:0]  req_wstrb;
    logic        req_ready;
    logic        resp_valid;
    logic [31:0] resp_value;
    logic [31:0] irqs;
    logic        mei, sei;

    plic dut (
        .clk_i       (clk),
        .rst_ni      (rst_n),
        .req_valid_i (req_valid),
        .req_addr_i  (req_addr),
        .req_value_i (req_value),
        .req_wstrb_i (req_wstrb),
        .req_ready_o (req_ready),
        .resp_valid_o(resp_valid),
        .resp_value_o(resp_value),
        .irqs_i      (irqs),
        .mei_o       (mei),
        .sei_o       (sei)
    );

    // Clock: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    int pass_cnt = 0;
    int fail_cnt = 0;

    // Bus write: drive addr (byte address), value, wstrb=0xF for one cycle
    task automatic bus_write(input logic [31:0] addr, input logic [31:0] val);
        @(posedge clk);
        req_valid <= 1;
        req_addr  <= addr;
        req_value <= val;
        req_wstrb <= 4'hF;
        @(posedge clk);
        req_valid <= 0;
        // Wait for resp_valid
        while (!resp_valid) @(posedge clk);
    endtask

    // Bus read: drive addr (byte address), wstrb=0 for one cycle, return resp
    task automatic bus_read(input logic [31:0] addr, output logic [31:0] val);
        @(posedge clk);
        req_valid <= 1;
        req_addr  <= addr;
        req_value <= 32'b0;
        req_wstrb <= 4'h0;
        @(posedge clk);
        req_valid <= 0;
        while (!resp_valid) @(posedge clk);
        val = resp_value;
    endtask

    task automatic check(input string name, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin
            $display("  PASS: %s = 0x%08x", name, got);
            pass_cnt++;
        end else begin
            $display("  FAIL: %s = 0x%08x (expected 0x%08x)", name, got, exp);
            fail_cnt++;
        end
    endtask

    logic [31:0] rd;

    initial begin
        $dumpfile("plic_tb.vcd");
        $dumpvars(0, plic_tb);

        // Init
        req_valid = 0;
        req_addr  = 0;
        req_value = 0;
        req_wstrb = 0;
        irqs      = 0;
        rst_n     = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // =====================================================
        $display("\n=== Test 1: Priority reads return 1 ===");
        // =====================================================
        bus_read(32'h0000_0004, rd);  // Priority for IRQ 1
        check("prio[1]", rd, 32'h1);
        bus_read(32'h0000_0014, rd);  // Priority for IRQ 5
        check("prio[5]", rd, 32'h1);

        // =====================================================
        $display("\n=== Test 2: Enable context 0, check readback ===");
        // =====================================================
        bus_write(32'h0000_2000, 32'h0000_0022);  // Enable IRQ 1 and 5 in context 0
        bus_read(32'h0000_2000, rd);
        check("enable0", rd, 32'h0000_0022);

        // =====================================================
        $display("\n=== Test 3: Enable context 1, check readback ===");
        // =====================================================
        bus_write(32'h0000_2080, 32'h0000_0004);  // Enable IRQ 2 in context 1
        bus_read(32'h0000_2080, rd);
        check("enable1", rd, 32'h0000_0004);

        // =====================================================
        $display("\n=== Test 4: Assert IRQ 1, check pending ===");
        // =====================================================
        irqs = 32'h0000_0002;  // IRQ 1 high
        @(posedge clk); @(posedge clk);  // Let pending update
        bus_read(32'h0000_1000, rd);
        check("pending (irq1)", rd, 32'h0000_0002);

        // =====================================================
        $display("\n=== Test 5: mei_o asserted (ctx0 has irq1 enabled+pending) ===");
        // =====================================================
        check("mei_o", {31'b0, mei}, 32'h1);

        // =====================================================
        $display("\n=== Test 6: sei_o deasserted (ctx1 irq1 not enabled) ===");
        // =====================================================
        check("sei_o", {31'b0, sei}, 32'h0);

        // =====================================================
        $display("\n=== Test 7: Claim ctx0 returns IRQ 1 ===");
        // =====================================================
        bus_read(32'h0020_0004, rd);
        check("claim0", rd, 32'h0000_0001);

        // =====================================================
        $display("\n=== Test 8: After claim, mei_o deasserts (irq claimed) ===");
        // =====================================================
        @(posedge clk); @(posedge clk);  // Let claimed propagate to pending
        check("mei_o after claim", {31'b0, mei}, 32'h0);

        // =====================================================
        $display("\n=== Test 9: Complete ctx0 IRQ 1, then re-assert ===");
        // =====================================================
        bus_write(32'h0020_0004, 32'h0000_0001);  // Complete IRQ 1
        @(posedge clk); @(posedge clk);
        // IRQ 1 still asserted on irqs_i, so pending should come back
        bus_read(32'h0000_1000, rd);
        check("pending after complete", rd, 32'h0000_0002);
        check("mei_o re-asserted", {31'b0, mei}, 32'h1);

        // =====================================================
        $display("\n=== Test 10: Deassert IRQ, pending clears ===");
        // =====================================================
        irqs = 32'h0;
        @(posedge clk); @(posedge clk);
        bus_read(32'h0000_1000, rd);
        check("pending cleared", rd, 32'h0);
        check("mei_o cleared", {31'b0, mei}, 32'h0);

        // =====================================================
        $display("\n=== Test 11: Context 1 — IRQ 2 ===");
        // =====================================================
        irqs = 32'h0000_0004;  // IRQ 2
        @(posedge clk); @(posedge clk);
        check("sei_o (irq2 enabled ctx1)", {31'b0, sei}, 32'h1);
        check("mei_o (irq2 not enabled ctx0)", {31'b0, mei}, 32'h0);

        bus_read(32'h0020_1004, rd);  // Claim ctx1
        check("claim1", rd, 32'h0000_0002);
        @(posedge clk); @(posedge clk);
        check("sei_o after claim", {31'b0, sei}, 32'h0);

        bus_write(32'h0020_1004, 32'h0000_0002);  // Complete ctx1 IRQ 2
        @(posedge clk); @(posedge clk);
        check("sei_o after complete", {31'b0, sei}, 32'h1);  // Still asserted

        // =====================================================
        $display("\n=== Test 12: Threshold reads return 0 ===");
        // =====================================================
        bus_read(32'h0020_0000, rd);
        check("threshold0", rd, 32'h0);
        bus_read(32'h0020_1000, rd);
        check("threshold1", rd, 32'h0);

        // =====================================================
        $display("\n=== Test 13: IRQ 0 is always reserved (never pending) ===");
        // =====================================================
        irqs = 32'h0000_0001;  // IRQ 0
        bus_write(32'h0000_2000, 32'hFFFF_FFFF);  // Enable all ctx0
        @(posedge clk); @(posedge clk);
        bus_read(32'h0000_1000, rd);
        check("pending irq0 masked", rd[0], 1'b0);

        // =====================================================
        // Summary
        // =====================================================
        irqs = 0;
        repeat (4) @(posedge clk);
        $display("\n========================================");
        $display("  %0d PASSED, %0d FAILED", pass_cnt, fail_cnt);
        $display("========================================\n");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
