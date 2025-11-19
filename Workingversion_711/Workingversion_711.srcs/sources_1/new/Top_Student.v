// ======================= Top_Student.v (clean, deduped) =======================
`timescale 1ns / 1ps
module Top_Student (
  input         basys_clock,
  output   [3:0] an,
  output   [6:0] seg,
  output         dp,
  output   [7:0] JC,
  output   [7:0] JXADC,
  input          btnC,
  input          btnU,
  input          btnL,
  input          btnR,
  input          btnD,             // reused for scale_control Y-zoom down in graph mode
  input  [15:0]  sw,
  inout          ps2_clk,
  inout          ps2_data,
  output [15:0]  led
);

  // ---------------- Optimized clocks ----------------
  wire clk_6p25Mhz, slow_clk, clk_1khz;
  clock_divider div6p25 (.basys_clock(basys_clock), .m(8),        .desired_CLOCK(clk_6p25Mhz));
  clock_divider div1k  (.basys_clock(basys_clock), .m(49999),   .desired_CLOCK(clk_1khz));
  clock_divider divSlow (.basys_clock(basys_clock), .m(50000000), .desired_CLOCK(slow_clk)); // ~1 Hz

  // ---------------- OLED core - Input Display (JC) ----------------
  wire        fb_input, send_pix_input, samp_pix_input;
  wire [12:0] pixel_index_input;
  wire [15:0] keypad_colour;

  Oled_Display oled_input(
    .clk            (clk_6p25Mhz),
    .reset          (btnC),
    .frame_begin    (fb_input),
    .sending_pixels (send_pix_input),
    .sample_pixel   (samp_pix_input),
    .pixel_index    (pixel_index_input),
    .pixel_data     (keypad_colour),
    .cs             (JC[0]),
    .sdin           (JC[1]),
    .sclk           (JC[3]),
    .d_cn           (JC[4]),
    .resn           (JC[5]),
    .vccen          (JC[6]),
    .pmoden         (JC[7])
  );

  // ---------------- OLED core - Output Display (JXADC) ----------------
  wire        fb_output, send_pix_output, samp_pix_output;
  wire [12:0] pixel_index_output_raw;
  wire [12:0] pixel_index_output_flipped;
  wire [15:0] output_colour;

  // Flip the output display 180 degrees (96x64 display, max index = 6143)
  assign pixel_index_output_flipped = 13'd6143 - pixel_index_output_raw;

  Oled_Display oled_output(
    .clk            (clk_6p25Mhz),
    .reset          (btnC),
    .frame_begin    (fb_output),
    .sending_pixels (send_pix_output),
    .sample_pixel   (samp_pix_output),
    .pixel_index    (pixel_index_output_raw),
    .pixel_data     (output_colour),
    .cs             (JXADC[0]),
    .sdin           (JXADC[1]),
    .sclk           (JXADC[3]),
    .d_cn           (JXADC[4]),
    .resn           (JXADC[5]),
    .vccen          (JXADC[6]),
    .pmoden         (JXADC[7])
  );

  // ---------------- Mouse ----------------
  wire [11:0] mouse_x, mouse_y;
  wire [3:0]  mouse_z;
  wire        mouse_left, mouse_mid, mouse_right, mouse_new;

  reg  [11:0] value;
  reg         setx, sety, setmax_x, setmax_y;
  reg  [1:0]  init_state;

  always @(posedge basys_clock or posedge btnC) begin
    if (btnC) begin
      init_state <= 2'd0;
      value      <= 12'd0;
      setx       <= 1'b0;
      sety       <= 1'b0;
      setmax_x   <= 1'b0;
      setmax_y   <= 1'b0;
    end else begin
      setx <= 1'b0; sety <= 1'b0; setmax_x <= 1'b0; setmax_y <= 1'b0;
      case (init_state)
        2'd0: begin value <= 12'd95; setmax_x <= 1'b1; init_state <= 2'd1; end
        2'd1: begin value <= 12'd63; setmax_y <= 1'b1; init_state <= 2'd2; end
        default: ;
      endcase
    end
  end

  MouseCtl #(
    .SYSCLK_FREQUENCY_HZ(100000000),
    .CHECK_PERIOD_MS(500),
    .TIMEOUT_PERIOD_MS(100)
  ) u_mouse (
    .clk       (basys_clock),
    .rst       (btnC),
    .xpos      (mouse_x),
    .ypos      (mouse_y),
    .zpos      (mouse_z),
    .left      (mouse_left),
    .middle    (mouse_mid),
    .right     (mouse_right),
    .new_event (mouse_new),
    .value     (value),
    .setx      (setx),
    .sety      (sety),
    .setmax_x  (setmax_x),
    .setmax_y  (setmax_y),
    .ps2_clk   (ps2_clk),
    .ps2_data  (ps2_data)
  );

  // ---------------- Keypad UI ----------------
  wire [15:0] keypad_led;
  wire [4:0]  sym_code_raw;
  wire        sym_pulse_raw;
  // ---------------- Delete pulse from keypad_ui ----------------
  wire delete_pulse;  // Now comes from keypad_ui module
  
  // ---------------- Clear-on-next variables (declared early) ----------------
  reg [4:0] held_sym_code;
  reg       inject_held_sym;
  reg       clear_on_next;
  reg       buf_clear_pulse;
  keypad_ui u_keypad (
    .clk         (basys_clock),
    .rst         (btnC),
    .pixel_index (pixel_index_input),
    .pixel_color (keypad_colour),
    .mouse_l     (mouse_left),
    .mouse_r     (mouse_right),
    .mouse_x     (mouse_x),
    .mouse_y     (mouse_y),
    .pad_b       (sw[0]),
    .frame_begin (fb_input),
    .btnD        (btnD),
    .led_out     (keypad_led),
    .sym_pulse   (sym_pulse_raw),
    .sym_code    (sym_code_raw),
    .delete_pulse(delete_pulse)
  );


    
  

  // ---------------- Input buffer (calculator) ----------------
  wire [5*32-1:0] buf_bus;
  wire [5:0]      buf_len;

  // Hand-off Supervisor (decls up-front to use in ui_pulse)
  localparam SUP_IDLE    = 2'd0,
             SUP_WAIT_MD = 2'd1,
             SUP_PASS_PM = 2'd2;

  reg [1:0]  sup_state;
  reg        inject_eq_to_md;
  reg        hold_pm;
  reg [4:0]  held_pm_code;
  reg        emit_pm_pulse;
  reg        suppress_lock;
  reg        sup_to_add_pulse;
  reg  [1:0] pm_delay_ctr;
  reg        md_waiting_term;

  wire sup_busy;
  assign sup_busy = (sup_state != SUP_IDLE);

  // Base pulse gated by supervisor
  wire ui_pulse = sym_pulse_raw & ~sup_busy;

  // Route symbol to buffer: either from UI or from held symbol injection
  wire       sym_pulse_to_buf = ui_pulse | inject_held_sym;
  wire [4:0] sym_code_to_buf  = inject_held_sym ? held_sym_code : sym_code_raw;
  
  sym_input_buffer #(.MAX_LEN(32)) u_buf (
    .basys_clock  (basys_clock),
    .rst          (btnC | buf_clear_pulse),
    .sym_pulse    (sym_pulse_to_buf),
    .sym_code     (sym_code_to_buf),
    .delete_pulse (delete_pulse),
    .len          (buf_len),
    .full         (),
    .empty        (),
    .buffer_bus   (buf_bus)
  );

  // ---------------- last_buf_sym (safe) ----------------
  reg  [4:0] last_buf_sym;
  always @* begin
    if (buf_len == 6'd0) 
      last_buf_sym = 5'd31;
    else if (buf_len <= 6'd16) begin
      case (buf_len)
        6'd1:  last_buf_sym = buf_bus[  4:  0];
        6'd2:  last_buf_sym = buf_bus[  9:  5];
        6'd3:  last_buf_sym = buf_bus[ 14: 10];
        6'd4:  last_buf_sym = buf_bus[ 19: 15];
        6'd5:  last_buf_sym = buf_bus[ 24: 20];
        6'd6:  last_buf_sym = buf_bus[ 29: 25];
        6'd7:  last_buf_sym = buf_bus[ 34: 30];
        6'd8:  last_buf_sym = buf_bus[ 39: 35];
        6'd9:  last_buf_sym = buf_bus[ 44: 40];
        6'd10: last_buf_sym = buf_bus[ 49: 45];
        6'd11: last_buf_sym = buf_bus[ 54: 50];
        6'd12: last_buf_sym = buf_bus[ 59: 55];
        6'd13: last_buf_sym = buf_bus[ 64: 60];
        6'd14: last_buf_sym = buf_bus[ 69: 65];
        6'd15: last_buf_sym = buf_bus[ 74: 70];
        6'd16: last_buf_sym = buf_bus[ 79: 75];
        default: last_buf_sym = 5'd31;
      endcase
    end else begin
      last_buf_sym = buf_bus[159:155];  // position 32
    end
  end

  // ---------------- Classification ----------------
  wire is_pm   = (sym_code_raw[4:1] == 4'b0101);                          // +/-
  wire is_md   = (sym_code_raw[4:1] == 4'b0110);                          // x,/
  wire is_trig = (sym_code_raw >= 5'd19) && (sym_code_raw <= 5'd21);      // s/c/t

  reg seen_digit;

  // ---------------- Modes ----------------
  localparam MODE_NONE = 2'b00,
             MODE_ADD  = 2'b01,
             MODE_MD   = 2'b10,
             MODE_TRIG = 2'b11;

  reg [1:0] calc_mode; // written only here

  // =====================================================================
  // Graphing Mode (declare early so other logic can gate by it)
  // =====================================================================
  localparam G_IDLE=3'd0, G_WAIT_EQ=3'd1, G_ENTER_A=3'd2, G_ENTER_B=3'd3,
             G_ENTER_C=3'd4, G_ENTER_D=3'd5, G_PLOT=3'd6;

  reg [2:0]  g_state;
  reg        graph_mode;

  // Coeff entry buffer
  wire [5*32-1:0] gbuf_bus;
  wire [5:0]      gbuf_len;
  reg             gbuf_rst;

  // Parsed coefficients
  reg  signed [31:0] coeff_a, coeff_b, coeff_c, coeff_d;

  // Scale control / graph pixel
  wire [3:0] X_SCALE_gc, Y_SCALE_gc;
  wire [15:0] graph_px;

  wire in_graph_entry = (g_state==G_ENTER_A)||(g_state==G_ENTER_B)||(g_state==G_ENTER_C)||(g_state==G_ENTER_D);
  wire in_graph_plot  = (g_state==G_PLOT);

  // Engines disabled during graph entry/plot
  wire engine_enable = ~(in_graph_entry | in_graph_plot);

  // Original OK pulse now gated by engine_enable + not locked
  reg input_locked;
  wire sym_pulse_ok = ui_pulse & ~input_locked & engine_enable;

  // per-engine routing
  wire [4:0] sym_code_md  = inject_eq_to_md ? 5'd14 : sym_code_raw;
  wire       sym_pulse_md = inject_eq_to_md ? 1'b1  : (ui_pulse & engine_enable);

  wire [4:0] sym_code_add  = emit_pm_pulse ? held_pm_code : sym_code_raw;
  wire       sym_pulse_add = emit_pm_pulse ? 1'b1         : (ui_pulse & engine_enable);

  // ---------------- Engines ----------------
  // delete is blocked when input_locked
  wire delete_to_engines = delete_pulse & ~input_locked;

  // seed hand-off
  reg        seed_valid_r;
  reg [31:0] seed_mag_r;
  reg        seed_neg_r;
  reg [3:0]  seed_scale_r;

  wire [31:0] add_mag; wire add_neg; wire [15:0] add_low16;
  wire add_valid; wire add_overflow; wire [3:0] add_scale; wire add_is_decimal;

  wire [31:0] md_mag;  wire md_neg;  wire [15:0] md_low16;
  wire md_valid; wire md_overflow; wire md_div0; wire [3:0] md_scale; wire md_is_decimal;

  wire [31:0] trig_mag;  wire trig_neg; wire [15:0] trig_low16;
  wire trig_valid, trig_overflow, trig_div0;

  addsub_function #(.WIDTH(32), .MAX_SCALE(9)) u_addsub (
    .clk            (basys_clock),
    .rst            (btnC),
    .sym_pulse      (sym_pulse_add),
    .sym_code       (sym_code_add),
    .delete_pulse   (delete_to_engines),
    .delete_sym     (last_buf_sym),

    .seed_valid     (seed_valid_r),
    .seed_mag       (seed_mag_r),
    .seed_neg       (seed_neg_r),
    .seed_scale     (seed_scale_r),

    .sum_mag        (add_mag),
    .sum_neg        (add_neg),
    .sum_low16      (add_low16),
    .sum_valid      (add_valid),
    .overflow       (add_overflow),
    .res_scale      (add_scale),
    .res_is_decimal (add_is_decimal)
  );

  muldiv_function #(.WIDTH(32), .DEC_PLACES(3)) u_muldiv (
    .clk            (basys_clock),
    .rst            (btnC),
    .sym_pulse      (sym_pulse_md),
    .sym_code       (sym_code_md),
    .delete_pulse   (delete_to_engines),
    .delete_sym     (last_buf_sym),
    .res_mag        (md_mag),
    .res_neg        (md_neg),
    .res_low16      (md_low16),
    .res_valid      (md_valid),
    .overflow       (md_overflow),
    .div_by_zero    (md_div0),
    .res_scale      (md_scale),
    .res_is_decimal (md_is_decimal)
  );

  trig_unit_simple #(.WIDTH(32), .DEC_PLACES(4)) u_trig_simple (
    .clk          (basys_clock),
    .rst          (btnC),
    .sym_pulse    (sym_pulse_ok),
    .sym_code     (sym_code_raw),
    .res_mag      (trig_mag),
    .res_neg      (trig_neg),
    .res_low16    (trig_low16),
    .res_valid    (trig_valid),
    .overflow     (trig_overflow),
    .div_by_zero  (trig_div0),
    .res_scale    (),
    .res_is_decimal()
  );

  // Lock input after '=' (unless supervisor suppresses)
  always @(posedge basys_clock or posedge btnC) begin
    if (btnC) input_locked <= 1'b0;
    else if ((add_valid || md_valid || trig_valid) && !suppress_lock) input_locked <= 1'b1;
    else if (buf_clear_pulse) input_locked <= 1'b0;  // unlock when clearing
  end

  // seen_digit tracking (placed here after engine valid signals are declared)
  always @(posedge basys_clock or posedge btnC) begin
    if (btnC) seen_digit <= 1'b0;
    else if (buf_clear_pulse) seen_digit <= 1'b0;  // Reset when buffer clears
    else if (ui_pulse && (sym_code_raw <= 5'd9)) seen_digit <= 1'b1;
    else if (inject_held_sym && (held_sym_code <= 5'd9)) seen_digit <= 1'b1;  // Also set on injected digit
  end


  
  always @(posedge basys_clock or posedge btnC) begin
    if (btnC) begin
      clear_on_next   <= 1'b0;
      buf_clear_pulse <= 1'b0;
      held_sym_code   <= 5'd0;
      inject_held_sym <= 1'b0;
    end else begin
      buf_clear_pulse <= 1'b0;  // default: pulse for one cycle only
      inject_held_sym <= 1'b0;  // default: pulse for one cycle only
      
      // Set flag when result is valid (= was pressed)
      if ((add_valid || md_valid || trig_valid) && !suppress_lock && !graph_mode) begin
        clear_on_next <= 1'b1;
      end
      
      // Clear buffer on next input (digit or operator, but not delete)
      if (clear_on_next && sym_pulse_raw && !delete_pulse && 
          (sym_code_raw <= 5'd15 || (sym_code_raw >= 5'd10 && sym_code_raw <= 5'd13))) begin
        // Hold the symbol, clear buffer, then we'll re-inject it next cycle
        held_sym_code   <= sym_code_raw;
        buf_clear_pulse <= 1'b1;
        clear_on_next   <= 1'b0;
      end
      
      // Re-inject the held symbol after buffer was cleared
      if (buf_clear_pulse) begin
        inject_held_sym <= 1'b1;
      end
    end
  end

  // md_waiting_term bookkeeping
  always @(posedge basys_clock or posedge btnC) begin
    if (btnC) md_waiting_term <= 1'b0;
    else begin
      if (ui_pulse && is_md) md_waiting_term <= 1'b1;
      if (ui_pulse && ((sym_code_raw <= 5'd9) || (sym_code_raw == 5'd15) || (sym_code_raw == 5'd14)))
        md_waiting_term <= 1'b0;
      if (md_valid) md_waiting_term <= 1'b0;
    end
  end

  // CENTRALIZED mode driver
  always @(posedge basys_clock or posedge btnC) begin
    if (btnC) begin
      calc_mode <= MODE_NONE;
    end else if (sup_to_add_pulse) begin
      calc_mode <= MODE_ADD;
    end else begin
      // Reset mode when buffer clears (on next input after result)
      if (buf_clear_pulse) begin
        calc_mode <= MODE_NONE;
      end
      // Set mode based on input
      if (sym_pulse_ok) begin
        if (calc_mode==MODE_NONE) begin
          if (is_trig)                  calc_mode <= MODE_TRIG;
          else if (seen_digit && is_md) calc_mode <= MODE_MD;
          else if (seen_digit && is_pm) calc_mode <= MODE_ADD;
        end
      end
    end
  end

  // ---------------- MD error latch ----------------
  reg md_error_latched;
  always @(posedge basys_clock or posedge btnC) begin
    if (btnC) md_error_latched <= 1'b0;
    else begin
      if (md_valid && (md_div0 || md_overflow)) md_error_latched <= 1'b1;
      if (sym_pulse_ok) md_error_latched <= 1'b0;
    end
  end

  // ---------------- Result select & decimal streamer ----------------
  wire [31:0] sel_mag   = (calc_mode==MODE_TRIG) ? trig_mag   :
                          (calc_mode==MODE_MD)   ? md_mag     : add_mag;
  wire        sel_neg   = (calc_mode==MODE_TRIG) ? trig_neg   :
                          (calc_mode==MODE_MD)   ? md_neg     : add_neg;
  wire        sel_valid = (calc_mode==MODE_TRIG) ? trig_valid :
                          (calc_mode==MODE_MD)   ? md_valid   : add_valid;
  wire [3:0]  sel_scale = (calc_mode==MODE_TRIG) ? 4'd4       :
                          (calc_mode==MODE_MD)   ? md_scale   : add_scale;

  wire              stream_busy, stream_done;
  wire [5:0]        res_len_digits;
  wire [5*12-1:0]   res_bus_digits;

  localparam [4:0] CODE_E = 5'd28, CODE_R = 5'd30;
  wire [5*12-1:0] md_err_bus = { {(5*(12-3)){1'b0}}, CODE_R, CODE_R, CODE_E};
  wire [5:0]      md_err_len = 6'd3;
  wire            use_md_err_display = md_error_latched;

  wire stream_start = sel_valid & ~use_md_err_display;

  dec_streamer_scaled #(.WIDTH(32), .MAX_DIG(12)) u_stream (
    .clk        (basys_clock),
    .rst        (btnC),
    .start      (stream_start),
    .neg        (sel_neg),
    .magnitude  (sel_mag),
    .scale      (sel_scale),
    .busy       (stream_busy),
    .done       (stream_done),
    .len        (res_len_digits),
    .bus        (res_bus_digits)
  );

  // ---------------- Alt Radix Streamer + 7-seg ----------------
  wire [1:0] alt_mode   = (sw[4]) ? 2'd3 : (sw[3]) ? 2'd2 : (sw[2]) ? 2'd1 : 2'd0;
  wire       alt_enable = (alt_mode != 2'd0);

  wire [5*12-1:0] alt_res_bus;
  wire [5:0]      alt_res_len;
  wire            alt_busy, alt_done;

  seven_seg u_seven_seg(
    .basys_clock(basys_clock),
    .mode(alt_mode),
    .rst(btnC),
    .an(an),
    .seg(seg),
    .dp(dp)
  );

  // Reconvert store
  reg  [31:0] result_mag;  reg result_neg;  reg [3:0] result_scale;  reg result_stored;
  always @(posedge basys_clock or posedge btnC) begin
    if (btnC) begin
      result_mag    <= 32'd0;
      result_neg    <= 1'b0;
      result_scale  <= 4'd0;
      result_stored <= 1'b0;
    end else if (sel_valid) begin
      result_mag    <= sel_mag;
      result_neg    <= sel_neg;
      result_scale  <= sel_scale;
      result_stored <= 1'b1;
    end
  end

  reg        prev_alt_enable;  reg [1:0]  prev_alt_mode;  reg        recompute_pulse;
  always @(posedge basys_clock or posedge btnC) begin
    if (btnC) begin
      prev_alt_enable <= 1'b0;
      prev_alt_mode   <= 2'd0;
      recompute_pulse <= 1'b0;
    end else begin
      recompute_pulse <= 1'b0;
      if (result_stored) begin
        if (alt_enable && ~prev_alt_enable)                 recompute_pulse <= 1'b1;
        else if (alt_enable && (alt_mode != prev_alt_mode)) recompute_pulse <= 1'b1;
      end
      prev_alt_enable <= alt_enable;
      prev_alt_mode   <= alt_mode;
    end
  end

  sequential_radix_streamer #(.WIDTH(32), .MAX_RES(12), .FRAC_DIGS(8)) u_seq_radix (
    .clk       (basys_clock),
    .rst       (btnC),
    .start     ( (sel_valid & ~use_md_err_display) | recompute_pulse ),
    .enable    (alt_enable),
    .neg       (result_neg),
    .magnitude (result_mag),
    .scale     (result_scale),
    .mode      (alt_mode),
    .busy      (alt_busy),
    .done      (alt_done),
    .bus       (alt_res_bus),
    .len       (alt_res_len)
  );

  // Final result bus (hide in graph plot; show ER if MD error)
  wire [5*12-1:0] normal_bus = alt_enable ? alt_res_bus : res_bus_digits;
  wire [5:0]      normal_len = alt_enable ? alt_res_len : res_len_digits;

  wire [5*12-1:0] final_res_bus = graph_mode ? 60'd0 :
                                  (use_md_err_display ? md_err_bus : normal_bus);
  wire [5:0]      final_res_len = graph_mode ? 6'd0 :
                                  (use_md_err_display ? md_err_len : normal_len);

  // ---------------- Caret blink ----------------
  reg caret_blink_state;
  always @(posedge slow_clk or posedge btnC) begin
    if (btnC) caret_blink_state <= 1'b0;
    else      caret_blink_state <= ~caret_blink_state;
  end
  wire caret_phase  = caret_blink_state;
  wire caret_enable = ~input_locked;

  // =====================================================================
  // Graphing: buffers, scale, plot
  // =====================================================================
  // route only during coefficient entry
  wire sym_pulse_to_gbuf      = sym_pulse_raw & in_graph_entry;
  wire [4:0] sym_code_to_gbuf = sym_code_raw;

  sym_input_buffer #(.MAX_LEN(32)) u_gbuf (
    .basys_clock  (basys_clock),
    .rst          (btnC | gbuf_rst),
    .sym_pulse    (sym_pulse_to_gbuf),
    .sym_code     (sym_code_to_gbuf),
    .delete_pulse (1'b0),
    .len          (gbuf_len),
    .full         (),
    .empty        (),
    .buffer_bus   (gbuf_bus)
  );

  // Buttons to scale_control only in plot
  wire btnU_gc = in_graph_plot ? btnU : 1'b0;
  wire btnD_gc = in_graph_plot ? btnD : 1'b0;
  wire btnL_gc = in_graph_plot ? btnL : 1'b0;
  wire btnR_gc = in_graph_plot ? btnR : 1'b0;

  scale_control u_scale (
    .clk        (clk_1khz),
    .rst        (btnC | (g_state == G_ENTER_A)),
    .graph_mode (in_graph_plot),
    .btnU       (btnU_gc),
    .btnD       (btnD_gc),
    .btnL       (btnL_gc),
    .btnR       (btnR_gc),
    .X_SCALE    (X_SCALE_gc),
    .Y_SCALE    (Y_SCALE_gc)
  );

  Graph_Plot u_graph (
    .pixel_index (pixel_index_output_flipped),
    .a           (coeff_a),
    .b           (coeff_b),
    .c           (coeff_c),
    .d           (coeff_d),
    .x_origin    (7'd48),
    .y_origin    (7'd32),
    .X_SCALE     (X_SCALE_gc),
    .Y_SCALE     (Y_SCALE_gc),
    .pixel_data  (graph_px)
  );

  // parse helper
  function signed [31:0] parse_int_from_buf;
    input [5*32-1:0] bus;
    input [5:0]      blen;
    integer i;
    reg signed [31:0] acc;
    reg neg;
    reg [4:0] code;
  begin
    acc = 0;
    neg = 1'b0;
    for (i=0; i<8; i=i+1) begin
      if (i < blen) begin
        case (i)
          0: code = bus[  4:  0];
          1: code = bus[  9:  5];
          2: code = bus[ 14: 10];
          3: code = bus[ 19: 15];
          4: code = bus[ 24: 20];
          5: code = bus[ 29: 25];
          6: code = bus[ 34: 30];
          7: code = bus[ 39: 35];
          default: code = 5'd31;
        endcase
        if (code == 5'd11) neg = 1'b1;                  
        else if (code <= 5'd9) acc = acc*10 + code[3:0];
      end
    end
    parse_int_from_buf = neg ? -acc : acc;
  end
  endfunction

  // Store the entered coefficient strings for display
  reg [5*32-1:0] stored_a_buf, stored_b_buf, stored_c_buf, stored_d_buf;
  reg [5:0] stored_a_len, stored_b_len, stored_c_len, stored_d_len;

  // Graph FSM
  always @(posedge basys_clock or posedge btnC) begin
    if (btnC) begin
      g_state    <= G_IDLE;
      graph_mode <= 1'b0;
      gbuf_rst   <= 1'b1;
      coeff_a    <= 32'sd0;
      coeff_b    <= 32'sd0;
      coeff_c    <= 32'sd0;
      coeff_d    <= 32'sd0;
      stored_a_buf <= 160'd0; stored_a_len <= 6'd0;
      stored_b_buf <= 160'd0; stored_b_len <= 6'd0;
      stored_c_buf <= 160'd0; stored_c_len <= 6'd0;
      stored_d_buf <= 160'd0; stored_d_len <= 6'd0;
    end else begin
      gbuf_rst <= 1'b0;

      if (!graph_mode) begin
        if (sym_pulse_raw && sym_code_raw==5'd16) begin          // 'Y='
          g_state    <= G_ENTER_A;
          graph_mode <= 1'b1;
          gbuf_rst   <= 1'b1;
        end
      end

      case (g_state)
        G_IDLE: ; 

        G_ENTER_A: if (sym_pulse_raw && sym_code_raw==5'd14) begin
          coeff_a  <= parse_int_from_buf(gbuf_bus, gbuf_len);
          stored_a_buf <= gbuf_bus;
          stored_a_len <= gbuf_len;
          gbuf_rst <= 1'b1;
          g_state  <= G_ENTER_B;
        end

        G_ENTER_B: if (sym_pulse_raw && sym_code_raw==5'd14) begin
          coeff_b  <= parse_int_from_buf(gbuf_bus, gbuf_len);
          stored_b_buf <= gbuf_bus;
          stored_b_len <= gbuf_len;
          gbuf_rst <= 1'b1;
          g_state  <= G_ENTER_C;
        end

        G_ENTER_C: if (sym_pulse_raw && sym_code_raw==5'd14) begin
          coeff_c  <= parse_int_from_buf(gbuf_bus, gbuf_len);
          stored_c_buf <= gbuf_bus;
          stored_c_len <= gbuf_len;
          gbuf_rst <= 1'b1;
          g_state  <= G_ENTER_D;
        end

        G_ENTER_D: if (sym_pulse_raw && sym_code_raw==5'd14) begin
          coeff_d  <= parse_int_from_buf(gbuf_bus, gbuf_len);
          stored_d_buf <= gbuf_bus;
          stored_d_len <= gbuf_len;
          gbuf_rst <= 1'b1;
          g_state  <= G_PLOT;
        end

        G_PLOT: begin
          if (sym_pulse_raw && sym_code_raw==5'd16) begin
            g_state    <= G_ENTER_A;
            gbuf_rst   <= 1'b1;
          end
        end
      endcase

      if (g_state==G_IDLE) graph_mode <= 1'b0;
    end
  end

  // ---------------- Output strip (prompt during graph entry) ---------------
  wire px_on_text, px_on_bg;

  wire [4:0] prompt_letter =
      (g_state == G_ENTER_A) ? 5'd24 :
      (g_state == G_ENTER_B) ? 5'd25 :
      (g_state == G_ENTER_C) ? 5'd26 :
      (g_state == G_ENTER_D) ? 5'd27 : 5'd23;

  wire [5*32-1:0] prompt_bus = {150'd0, 5'd14, prompt_letter};  // "X="
  wire [5:0]      prompt_len = in_graph_entry ? 6'd2 : 6'd0;

  wire [5*32-1:0] combined_gbuf = in_graph_entry ?
                                  ((gbuf_len == 0) ? prompt_bus :
                                   {gbuf_bus[149:0], prompt_bus[9:0]}) :
                                  gbuf_bus;
  wire [5:0] combined_glen = in_graph_entry ?
                             ((gbuf_len == 0) ? prompt_len : gbuf_len + prompt_len) :
                             gbuf_len;

    // ---------------- Equation display builder ---------------
  // Show: "a=## b=## c=## d=##" with negative signs
  // Symbol map: '='=14, space=31, minus=11, a=24, b=25, c=26, d=27, digits 0..9 -> 0..9

  localparam [4:0] SYM_EQ    = 5'd14;
  localparam [4:0] SYM_SP    = 5'd31;
  localparam [4:0] SYM_PLUS  = 5'd10;
  localparam [4:0] SYM_MINUS = 5'd11;
  localparam [4:0] SYM_a     = 5'd24;
  localparam [4:0] SYM_b     = 5'd25;
  localparam [4:0] SYM_c     = 5'd26;
  localparam [4:0] SYM_d     = 5'd27;

  // Sign bits
  wire a_neg = coeff_a[31];
  wire b_neg = coeff_b[31];
  wire c_neg = coeff_c[31];
  wire d_neg = coeff_d[31];

  // Absolute values (clamped to 0..99)
  wire [31:0] a_abs32 = a_neg ? (~coeff_a + 1) : coeff_a;
  wire [31:0] b_abs32 = b_neg ? (~coeff_b + 1) : coeff_b;
  wire [31:0] c_abs32 = c_neg ? (~coeff_c + 1) : coeff_c;
  wire [31:0] d_abs32 = d_neg ? (~coeff_d + 1) : coeff_d;

  wire [6:0] a_mod100 = a_abs32 % 100;
  wire [6:0] b_mod100 = b_abs32 % 100;
  wire [6:0] c_mod100 = c_abs32 % 100;
  wire [6:0] d_mod100 = d_abs32 % 100;

  // Tens/ones digits as 5-bit symbols (0..9)
  wire [4:0] a_tens = a_mod100 / 10;
  wire [4:0] a_ones = a_mod100 % 10;
  wire [4:0] b_tens = b_mod100 / 10;
  wire [4:0] b_ones = b_mod100 % 10;
  wire [4:0] c_tens = c_mod100 / 10;
  wire [4:0] c_ones = c_mod100 % 10;
  wire [4:0] d_tens = d_mod100 / 10;
  wire [4:0] d_ones = d_mod100 % 10;

  // Sign symbols (minus or space)
  wire [4:0] a_sign = a_neg ? SYM_MINUS : SYM_PLUS;
  wire [4:0] b_sign = b_neg ? SYM_MINUS : SYM_PLUS;
  wire [4:0] c_sign = c_neg ? SYM_MINUS : SYM_PLUS;
  wire [4:0] d_sign = d_neg ? SYM_MINUS : SYM_PLUS;

  // Bus & length
  wire [5*32-1:0] equation_bus;
  wire [5:0]      equation_len;
  
  // Build in REVERSE order (d,c,b,a) so it displays as a,b,c,d on screen
  // Format: a=[sign]## b=[sign]## c=[sign]## d=[sign]##
  assign equation_bus = in_graph_plot ? {
    // d=[sign]##
    d_ones, d_tens, d_sign, SYM_EQ, SYM_d,
    SYM_SP,
    // c=[sign]##
    c_ones, c_tens, c_sign, SYM_EQ, SYM_c,
    SYM_SP,
    // b=[sign]##
    b_ones, b_tens, b_sign, SYM_EQ, SYM_b,
    SYM_SP,
    // a=[sign]##
    a_ones, a_tens, a_sign, SYM_EQ, SYM_a
  } : {5*32{1'b0}};

  assign equation_len = in_graph_plot ? 6'd23 : 6'd0;

  wire [5*32-1:0] strip_buf_bus = in_graph_plot ? equation_bus :
                                  (in_graph_entry ? combined_gbuf : buf_bus);
  wire [5:0]      strip_len     = in_graph_plot ? equation_len :
                                  (in_graph_entry ? combined_glen : buf_len);

  Output_strip #(
    .DISP_W    (96), .DISP_H(64), .CELL_W(10), .CELL_H(14),
    .PAD_L(2), .PAD_T(1), .PAD_B(1), .MAX_LEN(32), .MAX_RES(12), .CARET_W_PX(2),
    .TOP_GAP(2)
  ) u_strip (
    .clk          (basys_clock),
    .rst          (btnC),
    .pixel_index  (pixel_index_output_flipped),
    .buffer_bus   (strip_buf_bus),
    .len          (strip_len),
    .res_bus      (final_res_bus),
    .res_len      (final_res_len),
    .caret_enable (~input_locked),
    .caret_phase  (caret_blink_state),
    .frame_begin  (fb_output),
    .btnL         (btnL),
    .btnR         (btnR),
    .px_on_text   (px_on_text),
    .px_on_bg     (px_on_bg)
  );

  // ---------------- Colors & LEDs ----------------
  localparam BLACK = 16'b00000_000000_00000;
  localparam GREY  = 16'b10101_101010_10101;
  localparam WHITE = 16'b11111_111111_11111;

  // Output display: sw[1] toggles between text/equation and graph when in plot mode
  wire show_graph = in_graph_plot && sw[1];
  wire [15:0] text_colour = (px_on_text || px_on_bg) ? (px_on_text ? BLACK : GREY) : GREY;
  assign output_colour = show_graph ? graph_px : text_colour;

  // Blink state for LED
  reg led_blink_state;
  always @(posedge slow_clk or posedge btnC) begin
    if (btnC) led_blink_state <= 1'b0;
    else      led_blink_state <= ~led_blink_state;
  end

  assign led = use_md_err_display ? (led_blink_state ? 16'hFFFF : 16'h0000)
                                  : 16'h0000;

  // ---------------- Supervisor FSM ----------------
  always @(posedge basys_clock or posedge btnC) begin
    if (btnC) begin
      sup_state        <= SUP_IDLE;
      inject_eq_to_md  <= 1'b0;
      hold_pm          <= 1'b0;
      held_pm_code     <= 5'd0;
      emit_pm_pulse    <= 1'b0;
      suppress_lock    <= 1'b0;
      seed_valid_r     <= 1'b0; seed_mag_r <= 32'd0; seed_neg_r <= 1'b0; seed_scale_r <= 4'd0;
      sup_to_add_pulse <= 1'b0;
      pm_delay_ctr     <= 2'd0;
    end else begin
      inject_eq_to_md  <= 1'b0;
      emit_pm_pulse    <= 1'b0;
      seed_valid_r     <= 1'b0;
      suppress_lock    <= 1'b0;
      sup_to_add_pulse <= 1'b0;

      case (sup_state)
        SUP_IDLE: begin
          if ((calc_mode==MODE_MD) && (ui_pulse & engine_enable) &&
              ((sym_code_raw==5'd10) || (sym_code_raw==5'd11)) &&
              !md_waiting_term) begin
            hold_pm          <= 1'b1;
            held_pm_code     <= sym_code_raw;
            inject_eq_to_md  <= 1'b1;
            suppress_lock    <= 1'b1;
            sup_state        <= SUP_WAIT_MD;
          end
        end

        SUP_WAIT_MD: begin
          suppress_lock <= 1'b1;
          if (md_valid) begin
            seed_mag_r      <= md_mag;
            seed_neg_r      <= md_neg;
            seed_scale_r    <= md_scale;
            seed_valid_r    <= 1'b1;

            sup_to_add_pulse<= 1'b1;
            pm_delay_ctr    <= 2'd2;
            sup_state       <= SUP_PASS_PM;
          end
        end

        SUP_PASS_PM: begin
          suppress_lock <= 1'b1;
          if (pm_delay_ctr != 0) begin
            pm_delay_ctr <= pm_delay_ctr - 2'd1;
          end else begin
            if (hold_pm) begin
              emit_pm_pulse <= 1'b1;
              hold_pm       <= 1'b0;
            end
            sup_state     <= SUP_IDLE;
          end
        end

        default: sup_state <= SUP_IDLE;
      endcase
    end
  end

endmodule
