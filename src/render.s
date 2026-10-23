; render.s - the dance floor in the multicolor bitmap, a port of the parts of draw.ts
; that draw the world: floor with grain and lights, furniture, the people, the frame
; of LEDs, the waiting arrows; and the renderer's own state (lights, timers) that
; advances once per tick and reacts to the game's events.
;
; A cell is 2x2 blocks of 4x8 multicolor pixels. Its pixels come from 32 bytes of
; gen/cells.bin or gen/figures.bin, its colours from the screen RAM (01 high nibble,
; 10 low nibble) and the colour RAM (11). The 01 colour of floor cells is the floor
; colour, which the lights change; people stand on the plain dance floor.
;
; Each frame the people, arrows and animated furniture are placed as objects; a
; cell is only drawn when its object changed, and cells left by objects get their
; base (floor or furniture) again.

OBJ_BASE   = 0              ; scode: the base is drawn
OBJ_PERSON = $80            ; scode: $80 | frame (bit 0 legs, bit 1 arms up) | $04 golden
OBJ_NONE   = $ff            ; scode: unknown (to be drawn)

.segment "BSS"
; per cell: the base graphic and its colours
b_gfx:      .res CELLS
b_top_hi:   .res CELLS      ; colour 01 of the top blocks, $ff: the floor colour
b_top_lo:   .res CELLS
b_top_col:  .res CELLS
b_bot_hi:   .res CELLS
b_bot_lo:   .res CELLS
b_bot_col:  .res CELLS
b_anim:     .res CELLS      ; furniture animation: 0 none, 1 mixer, 2 turntable, 3 speaker
b_run:      .res CELLS      ; index in the run of DJ desk cells
; what is drawn
scode:      .res CELLS
slook:      .res CELLS
stamp:      .res CELLS
fcur:       .res CELLS      ; the floor colour shown
fmask:      .res CELLS      ; bit 0: the top blocks use the floor colour, bit 1: the bottom blocks
; the objects of the last frame
shown:      .res CELLS
shown_n:    .res 1
shown2:     .res CELLS
shown2_n:   .res 1
frame_id:   .res 1
crow_vis:   .res ROWS       ; 1: the cell row is shown (both character rows bitmap)

; the renderer's state (draw.ts)
r_ticks:    .res 2
r_bphase:   .res 1          ; ticks into the beat (0..29)
r_b5:       .res 1          ; the beat number modulo 5, 3, 23, 2
r_b3:       .res 1
r_b23:      .res 1
r_b2:       .res 1
r_t8:       .res 1          ; ticks / 8
r_t8c:      .res 1
r_t15:      .res 1          ; ticks / 15
r_t15c:     .res 1
r_t20:      .res 1          ; ticks / 20
r_t20c:     .res 1
r_t10:      .res 1          ; ticks / 10 (mixer faders)
r_t10c:     .res 1
light:      .res CELLS
lightcol:   .res CELLS
LIT_MAX = 24
lit_cells:  .res LIT_MAX
lit_n:      .res 1
flee_mark:  .res MAX_GUESTS
last_head:  .res 1
shake:      .res 1
screen_flash: .res 1
lives_flash: .res 1
combo_flash: .res 1
cleared_ticks: .res 1       ; 0: not cleared (counts up to 255)
hud_dirty:  .res 1
led_beat:   .res 1          ; the beat of the LED colours shown ($ff: redraw)
desk_beat:  .res 1
color_q:    .res 1          ; the quarter of the field of the colour pass
show_arrows: .res 1         ; the waiting arrows may be shown (game, not the demo)
field_on:   .res 1          ; the field is drawn at all

; temporaries
rd_cell:    .res 1
rd_code:    .res 1
rd_look:    .res 1
rd_hi_t:    .res 1
rd_hi_b:    .res 1
rd_lo_t:    .res 1
rd_col_t:   .res 1
rd_lo_b:    .res 1
rd_col_b:   .res 1
rd_i:       .res 1
rd_x:       .res 1
rd_gold:    .res 1
rd_lvl:     .res 1
rd_col:     .res 1
rd_n:       .res 1
rd_drawn:   .res 1
an_i:       .res 1

.segment "ZEROPAGE"
src:        .res 2
dst:        .res 2
dst2:       .res 2
scr:        .res 2
col:        .res 2

.segment "RODATA"

.include "gfx.inc"

figures_bin: .incbin "figures.bin"
cells_bin:  .incbin "cells.bin"

; bitmap address of the top left block of each cell
cell_bm_lo:
.repeat CELLS, i
        .byte <(BITMAP + (1 + 2 * (i / COLS)) * 320 + (1 + 2 * (i .mod COLS)) * 8)
.endrepeat
cell_bm_hi:
.repeat CELLS, i
        .byte >(BITMAP + (1 + 2 * (i / COLS)) * 320 + (1 + 2 * (i .mod COLS)) * 8)
.endrepeat
; screen offset of the top left block
cell_scr_lo:
.repeat CELLS, i
        .byte <((1 + 2 * (i / COLS)) * 40 + 1 + 2 * (i .mod COLS))
.endrepeat
cell_scr_hi:
.repeat CELLS, i
        .byte >((1 + 2 * (i / COLS)) * 40 + 1 + 2 * (i .mod COLS))
.endrepeat
; the beat patterns: (x * 5 + y * 3) % 23 and (x + y) % 3
cell_p23:
.repeat CELLS, i
        .byte ((i .mod COLS) * 5 + (i / COLS) * 3) .mod 23
.endrepeat
cell_p3:
.repeat CELLS, i
        .byte ((i .mod COLS) + (i / COLS)) .mod 3
.endrepeat
; (x * 2 + y) % 5 and x % 5
cell_p5c:
.repeat CELLS, i
        .byte ((i .mod COLS) * 2 + (i / COLS)) .mod 5
.endrepeat
cell_x5:
.repeat CELLS, i
        .byte (i .mod COLS) .mod 5
.endrepeat
; the first cell of each row
row_first:
.repeat ROWS, i
        .byte i * COLS
.endrepeat
; screen offsets of the character rows
row_scr_lo:
.repeat 25, i
        .byte <(i * 40)
.endrepeat
row_scr_hi:
.repeat 25, i
        .byte >(i * 40)
.endrepeat
row_bm_lo:
.repeat 25, i
        .byte <(BITMAP + i * 320)
.endrepeat
row_bm_hi:
.repeat 25, i
        .byte >(BITMAP + i * 320)
.endrepeat

; the colours of the disco lights (pink, cyan, yellow, green, violet) at the levels 1..3
lit_ramp:
        .byte BLUE, PURPLE, PURPLE, LRED
        .byte BLUE, LBLUE, LBLUE, CYAN
        .byte BLUE, ORANGE, ORANGE, YELLOW
        .byte BLUE, GREEN, GREEN, LGREEN
        .byte BLUE, PURPLE, LBLUE, LBLUE
; the bright colours of the lights (LEDs, desk)
lit_bright: .byte LRED, CYAN, YELLOW, LGREEN, LBLUE
; level of the beat pattern by the ticks into the beat
beat_level:
        .byte 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
; the turntable dot goes round in 42 ticks: frame by ticks / 10
mod3:       .byte 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2

; the colours of the furniture kinds: top 01, 10, 11, bottom 01, 10, 11
furn_tab_lo: .byte 0, <fcol_mixer, <fcol_table, <fcol_speaker, <fcol_bar
furn_tab_hi: .byte 0, >fcol_mixer, >fcol_table, >fcol_speaker, >fcol_bar

.segment "CODE"

; ---------------------------------------------------------------- setup

; Clears the renderer's state (a new song, or a new screen).
render_reset:
        ldx #CELLS - 1
        lda #0
@l:     sta light, x
        dex
        cpx #$ff
        bne @l
        ldx #MAX_GUESTS - 1
@f:     sta flee_mark, x
        dex
        bpl @f
        sta lit_n
        sta shake
        sta screen_flash
        sta cleared_ticks
        sta shake_x
        lda #$ff
        sta last_head
        sta led_beat
        sta desk_beat
        lda #$ff
        sta hud_dirty
        rts

; The base of every cell from the tiles of the game (after start_song).
field_setup:
        ldx #0
@c:     lda #$ff
        sta b_top_hi, x
        sta b_bot_hi, x
        lda #LBLUE
        sta b_top_lo, x
        sta b_bot_lo, x
        lda #YELLOW
        sta b_top_col, x
        sta b_bot_col, x
        lda #0
        sta b_anim, x
        sta b_run, x
        lda #BLUE
        sta fcur, x
        lda tile, x
        bne @furn
        ; floor: a grain variant from the cell number; dithered on the darker squares
        txa
        asl
        adc cell_x, x
        and #7
        asl
        sta b_gfx, x
        lda cell_x, x
        eor cell_y, x
        and #1
        ora b_gfx, x
        sta b_gfx, x
        jmp @next
@furn:  stx rd_cell
        tay
        lda furn_tab_lo, y
        sta src
        lda furn_tab_hi, y
        sta src + 1
        cpy #TILE_DJ
        bne @nd
        ; the DJ desk: mixers and turntables take turns
        jsr run_index
        sta b_run, x
        lsr
        bcs @tt
        lda #1
        sta b_anim, x
        lda #CELL_MIXER0
        bne @g
@tt:    lda #2
        sta b_anim, x
        lda #CELL_TURN0
        bne @g
@nd:    cpy #TILE_TABLE
        bne @ns
        lda #CELL_TABLE
        bne @g
@ns:    cpy #TILE_SPEAKER
        bne @nb
        lda #3
        sta b_anim, x
        lda #CELL_SPEAKER0
        bne @g
@nb:    txa
        and #1
        clc
        adc #CELL_BAR0
@g:     sta b_gfx, x
        ldy #0
        lda (src), y
        sta b_top_hi, x
        iny
        lda (src), y
        sta b_top_lo, x
        iny
        lda (src), y
        sta b_top_col, x
        iny
        lda (src), y
        sta b_bot_hi, x
        iny
        lda (src), y
        sta b_bot_lo, x
        iny
        lda (src), y
        sta b_bot_col, x
@next:  lda #OBJ_NONE
        sta scode, x
        inx
        cpx #CELLS
        beq @done
        jmp @c
@done:  lda #0
        sta shown_n
        sta cdirty_n
        lda #$ff
        sta led_beat
        sta desk_beat
        lda #1
        sta field_on
        lda #4
        sta full_q
        ; the animated furniture
        ldx #0
        ldy #0
@an:    lda b_anim, x
        beq @ann
        txa
        sta anim_cells, y
        iny
        cpy #16
        beq @and
@ann:   inx
        cpx #CELLS
        bne @an
@and:   sty anim_n
        rts

; A = the position of cell X in its run of DJ desk cells (X kept).
run_index:
        stx ri_c
        ldy #0
@l:     lda cell_x, x
        beq @d
        lda tile - 1, x
        cmp #TILE_DJ
        bne @d
        dex
        iny
        bne @l
@d:     ldx ri_c
        tya
        rts

.segment "BSS"
ri_c:       .res 1
.segment "CODE"

; Which cell rows are shown: both of their character rows in bitmap mode.
update_vis:
        ldx #0
@r:     txa
        asl
        tay
        lda rowmode + 1, y
        ora rowmode + 2, y
        bne @h
        lda #1
        bne @s
@h:     lda #0
@s:     sta crow_vis, x
        inx
        cpx #ROWS
        bne @r
        rts

; Draws the base of all cells of the cell rows A..X, also hidden ones (to show them next),
; with the LEDs of their character rows.
redraw_rows:
        sta rr_y
        stx rr_last
@row:   ldx rr_y
        lda row_first, x
        sta rr_c
        lda #COLS
        sta rr_n
@cell:  ldx rr_c
        lda #OBJ_BASE
        sta scode, x
        lda #BLUE
        sta fcur, x
        jsr draw_base
        inc rr_c
        dec rr_n
        bne @cell
        lda rr_y
        asl
        tax
        inx
        jsr draw_led_row
        inx
        jsr draw_led_row
        lda rr_y
        cmp rr_last
        beq @done
        inc rr_y
        bne @row
@done:  lda #$ff
        sta led_beat
        sta desk_beat
        lda #4
        sta full_q
        ; the objects there are drawn again
        ldx shown_n
        beq @x
@o:     ldy shown - 1, x
        lda scode, y
        cmp #OBJ_BASE
        bne @k
        lda #OBJ_NONE
        sta scode, y
@k:     dex
        bne @o
@x:     rts

.segment "BSS"
rr_y:       .res 1
rr_last:    .res 1
rr_c:       .res 1
rr_n:       .res 1
.segment "CODE"

; Draws all of the field (after field_setup).
redraw_field:
        lda #0
        ldx #ROWS - 1
        jmp redraw_rows

; ---------------------------------------------------------------- drawing a cell

; Draws the base of cell X.
draw_base:
        lda b_gfx, x
        ; fall through

; Draws the graphic A of gen/cells.bin with the colours of the base of cell X.
draw_gfx:
        stx rd_cell
        ; src = cells_bin + A * 32
        ldy #0
        sty src + 1
        asl
        asl
        rol src + 1
        asl
        rol src + 1
        asl
        rol src + 1
        asl
        rol src + 1
        clc
        adc #<cells_bin
        sta src
        lda src + 1
        adc #>cells_bin
        sta src + 1
        lda b_top_lo, x
        sta rd_lo_t
        lda b_top_col, x
        sta rd_col_t
        lda b_bot_lo, x
        sta rd_lo_b
        lda b_bot_col, x
        sta rd_col_b
        lda #0
        sta rd_n                ; floor mask
        lda b_top_hi, x
        cmp #$ff
        bne @t
        lda #1
        sta rd_n
        lda fcur, x
@t:     sta rd_hi_t
        lda b_bot_hi, x
        cmp #$ff
        bne @b
        lda rd_n
        ora #2
        sta rd_n
        lda fcur, x
@b:     sta rd_hi_b
        lda rd_n
        sta fmask, x
        lda #0
        sta rd_gold
        jmp blit

; Draws a person on cell X: rd_code = frame (bit 2 golden), rd_look = look.
draw_person:
        stx rd_cell
        ldy rd_look
        lda look_skin, y
        sta rd_lo_t
        lda look_hair, y
        sta rd_col_t
        lda look_shirt, y
        sta rd_lo_b
        lda look_leg, y
        sta rd_col_b
        lda look_shape, y
        ; src = figures_bin + (shape * 4 + frame) * 32
        asl
        asl
        sta rd_n
        lda rd_code
        and #3
        ora rd_n
        ldy #0
        sty src + 1
        asl
        rol src + 1
        asl
        rol src + 1
        asl
        rol src + 1
        asl
        rol src + 1
        asl
        rol src + 1
        clc
        adc #<figures_bin
        sta src
        lda src + 1
        adc #>figures_bin
        sta src + 1
        ; behind a person the plain dance floor: no lights (they show again when the
        ; person moves on, from fcur)
        lda #BLUE
        sta rd_hi_t
        sta rd_hi_b
        lda #0
        sta fmask, x
        lda rd_code
        and #4
        sta rd_gold
        beq blit
        ; a star: golden outline (11), hair and trousers black
        lda #YELLOW
        sta rd_col_t
        sta rd_col_b
        ; fall through

; Copies the 32 bytes at src into the cell rd_cell and sets its colours.
blit:
        ldx rd_cell
        lda cell_bm_lo, x
        sta dst
        clc
        adc #<(320 - 16)
        sta dst2
        lda cell_bm_hi, x
        sta dst + 1
        adc #>(320 - 16)
        sta dst2 + 1
        lda rd_gold
        bne @gold
        ldy #0
@top:   lda (src), y
        sta (dst), y
        iny
        cpy #16
        bne @top
@bot:   lda (src), y
        sta (dst2), y
        iny
        cpy #32
        bne @bot
        beq @colors
@gold:  ldy #0
@gt:    lda (src), y
        tax
        lda gold_xlat, x
        sta (dst), y
        iny
        cpy #16
        bne @gt
@gb:    lda (src), y
        tax
        lda gold_xlat, x
        sta (dst2), y
        iny
        cpy #32
        bne @gb
@colors:
        ldx rd_cell
        lda cell_scr_lo, x
        sta scr
        sta col
        lda cell_scr_hi, x
        clc
        adc #>SCREEN
        sta scr + 1
        adc #>(COLRAM - SCREEN)
        sta col + 1
        lda rd_hi_t
        asl
        asl
        asl
        asl
        ora rd_lo_t
        ldy #0
        sta (scr), y
        iny
        sta (scr), y
        lda rd_hi_b
        asl
        asl
        asl
        asl
        ora rd_lo_b
        ldy #40
        sta (scr), y
        iny
        sta (scr), y
        lda rd_col_t
        ldy #0
        sta (col), y
        iny
        sta (col), y
        lda rd_col_b
        ldy #40
        sta (col), y
        iny
        sta (col), y
        rts

; Sets the floor colour A of cell X (in the blocks that show it).
set_floor:
        sta fcur, x
        asl
        asl
        asl
        asl
        sta rd_n
        lda fmask, x
        beq @done
        sta rd_x
        lda cell_scr_lo, x
        sta scr
        lda cell_scr_hi, x
        clc
        adc #>SCREEN
        sta scr + 1
        lsr rd_x
        bcc @nt
        ldy #0
        lda (scr), y
        and #$0f
        ora rd_n
        sta (scr), y
        iny
        lda (scr), y
        and #$0f
        ora rd_n
        sta (scr), y
@nt:    lsr rd_x
        bcc @done
        ldy #40
        lda (scr), y
        and #$0f
        ora rd_n
        sta (scr), y
        iny
        lda (scr), y
        and #$0f
        ora rd_n
        sta (scr), y
@done:  rts

; ---------------------------------------------------------------- the frame of LEDs

; Draws the LED blocks of character row X (1..24) at the left and right edge (X kept).
draw_led_row:
        lda row_bm_lo, x
        sta dst
        lda row_bm_hi, x
        sta dst + 1
        ldy #7
@l:     lda cells_bin + CELL_LEDL * 32, y
        sta (dst), y
        dey
        bpl @l
        lda dst
        clc
        adc #<(39 * 8)
        sta dst
        lda dst + 1
        adc #>(39 * 8)
        sta dst + 1
        ldy #7
@r:     lda cells_bin + CELL_LEDR * 32 + 8, y
        sta (dst), y
        dey
        bpl @r
        rts

; The LED colours run along with the beat: led i shows seq[(i + b + k) % 3].
update_leds:
        lda r_b3
        cmp led_beat
        bne @go
        rts
@go:    sta led_beat
        ldx #1
@row:   lda rowmode, x
        bne @next
        lda row_scr_lo, x
        sta scr
        lda row_scr_hi, x
        clc
        adc #>SCREEN
        sta scr + 1
        ; LED index 2 * (row - 1) + b
        txa
        asl
        clc
        adc r_b3
        sta rd_n
        ; left: seq[(i + b + 2) % 3]
        jsr led_pair
        ldy #0
        sta (scr), y
        ; right: seq[(i + b) % 3]
        lda rd_n
        sec
        sbc #2
        sta rd_n
        jsr led_pair
        ldy #39
        sta (scr), y
@next:  inx
        cpx #25
        bne @row
        rts

; The screen byte of two LEDs i = rd_n, rd_n + 1 (i in 0..63).
led_pair:
        ldy rd_n
        lda mod3_tab, y
        tay
        lda led_seq, y
        asl
        asl
        asl
        asl
        sta rd_x
        ldy rd_n
        lda mod3_tab + 1, y
        tay
        lda led_seq, y
        ora rd_x
        rts

.segment "RODATA"
led_seq:    .byte LRED, CYAN, YELLOW
mod3_tab:
.repeat 264, i
        .byte i .mod 3
.endrepeat
mod5_tab:
.repeat 264, i
        .byte i .mod 5
.endrepeat
.segment "CODE"

; The LEDs of the DJ desk take the beat's colours: LED k of desk cell i shows
; LIT[(k + i + b) % 5]; the bottom blocks have two LED colours (01 and 11).
update_desk:
        lda r_b5
        cmp desk_beat
        bne @go
        rts
@go:    sta desk_beat
        ldx #0
@c:     lda tile, x
        cmp #TILE_DJ
        bne @next
        ldy cell_y, x
        lda crow_vis, y
        beq @next
        jsr desk_cell
@next:  inx
        cpx #CELLS
        bne @c
        rts

; The LED colours of the desk cell X (X kept).
desk_cell:
        stx dc_cell
        lda cell_scr_lo, x
        sta scr
        sta col
        lda cell_scr_hi, x
        clc
        adc #>SCREEN
        sta scr + 1
        adc #>(COLRAM - SCREEN)
        sta col + 1
        ; k = 0..3: blocks bottom left (k 0, 1) and bottom right (k 2, 3)
        lda b_run, x
        clc
        adc r_b5
        sta rd_n
        tay
        lda mod5_tab, y
        tay
        lda lit_bright, y
        asl
        asl
        asl
        asl
        ora #DGREY
        ldy #40
        sta (scr), y
        ldy rd_n
        lda mod5_tab + 1, y
        tay
        lda lit_bright, y
        ldy #40
        sta (col), y
        ldy rd_n
        lda mod5_tab + 2, y
        tay
        lda lit_bright, y
        asl
        asl
        asl
        asl
        ora #DGREY
        ldy #41
        sta (scr), y
        ldy rd_n
        lda mod5_tab + 3, y
        tay
        lda lit_bright, y
        ldy #41
        sta (col), y
        ldx dc_cell
        rts

.segment "BSS"
dc_cell:    .res 1
.segment "CODE"

; ---------------------------------------------------------------- objects

; Places the object rd_code / rd_look on cell X this frame.
place:
        ldy cell_y, x
        lda crow_vis, y
        beq @hidden
        lda frame_id
        sta stamp, x
        txa
        ldy shown2_n
        sta shown2, y
        inc shown2_n
        lda rd_code
        cmp scode, x
        bne @draw
        lda rd_look
        cmp slook, x
        beq @same
@draw:  lda #1
        sta rd_drawn
        lda rd_code
        sta scode, x
        lda rd_look
        sta slook, x
        lda rd_code
        bmi @person
        sec
        sbc #1
        jmp draw_gfx
@person:
        jmp draw_person
@hidden:
        lda #OBJ_NONE
        sta scode, x
@same:  rts

; All objects of this frame: the line, the guests, the arrows, the furniture animations.
place_objects:
        inc frame_id
        lda #0
        sta shown2_n
        ; the line
        ldx #0
        stx rd_i
@m:     lda r_ticks
        ldy phase
        cpy #PHASE_CLEARED
        bne @nd
        ; dancing: arms up on (ticks / 15 + i) % 2
        lda r_t15
        clc
        adc rd_i
        and #1
        asl
        sta rd_code
        jmp @lg
@nd:    lda #0
        sta rd_code
@lg:    lda steps
        clc
        adc rd_i
        and #1
        ora rd_code
        ora #OBJ_PERSON
        sta rd_code
        ldx rd_i
        lda look, x
        sta rd_look
        lda body, x
        tax
        jsr place
        inc rd_i
        lda rd_i
        cmp length
        bne @m
        ; the guests
        lda #0
        sta rd_i
@g:     ldx rd_i
        lda g_active, x
        beq @gn
        ; a star blinks before it leaves
        lda #0
        sta rd_gold
        lda g_type, x
        cmp #GUEST_STAR
        bne @ns
        lda #4
        sta rd_gold
        lda g_age_hi, x
        cmp #>(STAR_TICKS - 2 * TICK_HZ)
        bcc @ns
        bne @bl
        lda g_age_lo, x
        cmp #<(STAR_TICKS - 2 * TICK_HZ) + 1
        bcc @ns
@bl:    lda r_ticks
        and #4
        bne @gn
@ns:    ; tt = ticks / 8 + s * 3 + look; legs (tt / 2) % 2, arms (tt / 4) % 2
        txa
        asl
        adc rd_i
        adc g_look, x
        adc r_t8
        sta rd_n
        lsr
        and #1
        sta rd_code
        lda g_type, x
        cmp #GUEST_SHY
        bne @dan
        lda flee_mark, x
        beq @arms
        lda #2
        bne @or
@dan:   lda rd_n
        lsr
        and #2
@or:    ora rd_code
        sta rd_code
@arms:  lda rd_code
        ora rd_gold
        ora #OBJ_PERSON
        sta rd_code
        lda g_look, x
        sta rd_look
        lda g_cell, x
        tax
        jsr place
@gn:    inc rd_i
        lda rd_i
        cmp g_top
        bcs *+5
        jmp @g
        ; the arrows next to the waiting leader in the free directions
        lda show_arrows
        beq @na
        lda phase
        cmp #PHASE_PLAY
        bne @na
        lda moving
        bne @na
        lda r_t15
        and #1
        bne @na
        lda #0
        sta rd_i
@a:     lda body
        ldx rd_i
        jsr next_cell
        cmp #NO_CELL
        beq @an
        tax
        lda tile, x
        ora memb, x
        ora gmap, x
        bne @an
        lda rd_i
        clc
        adc #CELL_ARROW0 + 1
        sta rd_code
        lda #0
        sta rd_look
        jsr place
@an:    inc rd_i
        lda rd_i
        cmp #4
        bne @a
@na:    ; the furniture animations
        lda #0
        sta an_i
@f:     ldy an_i
        cpy anim_n
        beq @fdone
        ldx anim_cells, y
        lda b_anim, x
        stx rd_cell
        cmp #1
        bne @f2
        ; mixer: faders by (ticks / 10 + k + i) % 3
        lda r_t10
        clc
        adc b_run, x
        tay
        lda mod3_tab, y
        clc
        adc #CELL_MIXER0 + 1
        bne @fp
@f2:    cmp #2
        bne @f3
        ; turntable: the dot goes round
        lda r_ticks
        lsr
        lsr
        lsr
        and #3
        clc
        adc #CELL_TURN0 + 1
        bne @fp
@f3:    ; speaker: the cone pumps on the beat
        lda r_bphase
        cmp #9
        lda #CELL_SPEAKER0 + 1
        bcs @fp
        lda #CELL_SPEAKER1 + 1
@fp:    sta rd_code
        lda #0
        sta rd_look
        sta rd_drawn
        jsr place
        ldx rd_cell
        lda rd_drawn
        beq @fn
        lda b_anim, x
        cmp #3
        bcs @fn
        jsr desk_cell
        ldx rd_cell
@fn:    inc an_i
        jmp @f
@fdone:
        ; cells left by the objects of the last frame get their base again
        ldx shown_n
        beq @sw
@v:     stx rd_i
        ldy shown - 1, x
        lda stamp, y
        cmp frame_id
        beq @vk
        lda scode, y
        cmp #OBJ_BASE
        beq @vk
        tya
        tax
        ldy cell_y, x
        lda crow_vis, y
        beq @vh
        lda #OBJ_BASE
        sta scode, x
        jsr draw_base
        jmp @vk
@vh:    lda #OBJ_NONE
        sta scode, x
@vk:    ldx rd_i
        dex
        bne @v
@sw:    ; swap the lists
        ldx shown2_n
        stx shown_n
        beq @done
@cp:    lda shown2 - 1, x
        sta shown - 1, x
        dex
        bne @cp
@done:  rts

; ---------------------------------------------------------------- floor colours

; The floor colour of cell X into A: the beat pattern, the light show of a cleared
; song, the glow under the steps of the line.
floor_color:
        lda tile, x
        beq *+5
        jmp @base
        lda #0
        sta rd_lvl
        ; (x * 5 + y * 3 + b) % 23 == 0
        lda cell_p23, x
        clc
        adc r_b23
        cmp #23
        bcc @p
        sbc #23
@p:     cmp #0
        bne @nb
        ldy r_bphase
        lda beat_level, y
        sta rd_lvl
        lda cell_x5, x
        clc
        adc r_b5
        tay
        lda mod5_tab, y
        sta rd_col
@nb:    lda cleared_ticks
        beq @nc
        lda cell_p3, x
        clc
        adc r_b3
        tay
        lda mod3_tab, y
        bne @nc
        lda #2
        sta rd_lvl
        lda cell_p5c, x
        clc
        adc r_b5
        tay
        lda mod5_tab, y
        sta rd_col
@nc:    lda light, x
        beq @nl
        ldy #3
        cmp #37
        bcs @lv
        dey
        cmp #24
        bcs @lv
        dey
@lv:    cpy rd_lvl
        bcc @nl
        beq @nl
        sty rd_lvl
        lda lightcol, x
        sta rd_col
@nl:    lda rd_lvl
        beq @base
        lda rd_col
        asl
        asl
        ora rd_lvl
        tay
        lda lit_ramp, y
        rts
@base:  lda #BLUE
        rts

; Updates the floor colours that may have changed: the cells in the list of marked
; cells, and a quarter of the field while a full pass is pending (full_q).
color_pass:
        ldy cdirty_n
        beq @full
@d:     ldx cdirty - 1, y
        sty cp_y
        jsr color_cell
        ldy cp_y
        dey
        bne @d
        sty cdirty_n
@full:  lda full_q
        bne @q
        rts
@q:     dec full_q
        lda full_q
        and #3
        tay
        lda quarter_first, y
        tax
        lda quarter_last, y
        sta cp_end
@c:     ldy cell_y, x
        lda crow_vis, y
        beq @next
        jsr floor_color
        cmp fcur, x
        beq @next
        jsr set_floor
@next:  inx
        cpx cp_end
        bne @c
        rts

.segment "BSS"
cp_end:     .res 1
cp_y:       .res 1
CDIRTY_MAX = 64
cdirty:     .res CDIRTY_MAX
cdirty_n:   .res 1
full_q:     .res 1          ; quarters of a full colour pass still to do
pat_first:  .res 24         ; cells of each value of the beat pattern (x * 5 + y * 3) % 23
pat_cells:  .res CELLS
anim_cells: .res 16         ; the cells of animated furniture
anim_n:     .res 1
.segment "CODE"

; Marks cell X for the colour pass (X kept).
color_mark:
        ldy cdirty_n
        cpy #CDIRTY_MAX
        bcs @full
        txa
        sta cdirty, y
        inc cdirty_n
        rts
@full:  lda #4
        sta full_q
        rts

; Marks the cells of the beat pattern value A.
mark_pattern:
        tay
        lda pat_first + 1, y
        sta mp_end
        lda pat_first, y
        tay
@l:     cpy mp_end
        beq @r
        ldx pat_cells, y
        sty mp_y
        jsr color_mark
        ldy mp_y
        iny
        bne @l
@r:     rts

; The pattern value of beat b23: (23 - b) % 23.
pattern_of:
        eor #$ff
        sec
        adc #23
        cmp #23
        bcc @r
        lda #0
@r:     rts

; Sorts the cells by their beat pattern value (once at the start).
pattern_init:
        lda #0
        sta mp_y                ; next position
        ldx #0                  ; value
@v:     txa
        sta pi_v
        lda mp_y
        sta pat_first, x
        ldy #0
@c:     lda cell_p23, y
        cmp pi_v
        bne @n
        tya
        ldx mp_y
        sta pat_cells, x
        inc mp_y
@n:     iny
        cpy #CELLS
        bne @c
        ldx pi_v
        inx
        cpx #23
        bne @v
        lda mp_y
        sta pat_first, x
        rts

.segment "BSS"
mp_end:     .res 1
mp_y:       .res 1
pi_v:       .res 1
.segment "CODE"

; Updates the floor colour of cell X at once.
color_cell:
        ldy cell_y, x
        lda crow_vis, y
        beq @done
        jsr floor_color
        cmp fcur, x
        beq @done
        jmp set_floor
@done:  rts

.segment "RODATA"
quarter_first: .byte 0, 57, 114, 171
quarter_last:  .byte 57, 114, 171, CELLS
; a byte of 4 multicolor pixels with 00 and 11 swapped (the golden star)
gold_xlat:
.repeat 256, i
        .byte i ^ ((((i >> 6) & 3) = 0 || ((i >> 6) & 3) = 3) * $c0) ^ ((((i >> 4) & 3) = 0 || ((i >> 4) & 3) = 3) * $30) ^ ((((i >> 2) & 3) = 0 || ((i >> 2) & 3) = 3) * $0c) ^ (((i & 3) = 0 || (i & 3) = 3) * $03)
.endrepeat
.segment "CODE"

; ---------------------------------------------------------------- ticks and events

; Advances the renderer by one tick (draw.ts tick()).
render_tick:
        inc r_ticks
        bne @t
        inc r_ticks + 1
@t:     ; counters of ticks / n
        inc r_t8c
        lda r_t8c
        cmp #8
        bcc @t8
        lda #0
        sta r_t8c
        inc r_t8
@t8:    inc r_t10c
        lda r_t10c
        cmp #10
        bcc @t10
        lda #0
        sta r_t10c
        inc r_t10
@t10:   inc r_t15c
        lda r_t15c
        cmp #15
        bcc @t15
        lda #0
        sta r_t15c
        inc r_t15
@t15:   inc r_t20c
        lda r_t20c
        cmp #20
        bcc @t20
        lda #0
        sta r_t20c
        inc r_t20
@t20:   inc r_bphase
        lda r_bphase
        cmp #8                  ; the beat pattern gets dimmer
        beq @lvl
        cmp #18
        bne @nlvl
@lvl:   lda r_b23
        jsr pattern_of
        jsr mark_pattern
        lda r_bphase
@nlvl:  cmp #BEAT_TICKS
        bcc @nb
        lda r_b23               ; the old pattern goes dark
        jsr pattern_of
        jsr mark_pattern
        lda cleared_ticks
        beq @ncl
        lda #4
        sta full_q
@ncl:   lda #0
        sta r_bphase
        ldx r_b5
        inx
        cpx #5
        bcc @b5
        ldx #0
@b5:    stx r_b5
        ldx r_b3
        inx
        cpx #3
        bcc @b3
        ldx #0
@b3:    stx r_b3
        ldx r_b23
        inx
        cpx #23
        bcc @b23
        ldx #0
@b23:   stx r_b23
        lda r_b2
        eor #1
        sta r_b2
        lda r_b23               ; the new pattern lights up
        jsr pattern_of
        jsr mark_pattern
@nb:
        ; the glow of the floor tiles fades
        ldx lit_n
        beq @nl
@l:     ldy lit_cells - 1, x
        lda light, y
        beq @rm
        sec
        sbc #1
        sta light, y
        cmp #36
        beq @lm
        cmp #23
        beq @lm
        cmp #0
        bne @lk
        jsr lmark
        jmp @rm
@lm:    jsr lmark
        jmp @lk
@rm:    ; remove from the list: the last entry takes its place
        ldy lit_n
        lda lit_cells - 1, y
        sta lit_cells - 1, x
        dec lit_n
@lk:    dex
        bne @l
@nl:    ; (the browser version lights the tiles under the steps of the line; here the
        ; line keeps the plain dance floor, without a trail of lit tiles behind it)
@nh:    ldx #MAX_GUESTS - 1
@fm:    lda flee_mark, x
        beq @fn
        dec flee_mark, x
@fn:    dex
        bpl @fm
        lda cleared_ticks
        beq @nc
        cmp #255
        beq @nc
        inc cleared_ticks
@nc:    lda shake
        beq @ns
        dec shake
@ns:    lda screen_flash
        beq @nf
        dec screen_flash
@nf:    lda lives_flash
        beq @nlf
        dec lives_flash
        lda lives_flash
        and #7
        bne @nlf
        lda #HUD_LIVES
        ora hud_dirty
        sta hud_dirty
@nlf:   lda combo_flash
        beq @ncf
        dec combo_flash
        lda combo_flash
        and #3
        bne @ncf
        lda #HUD_COMBO
        ora hud_dirty
        sta hud_dirty
@ncf:   ; the combo time runs down
        lda combo_timer
        and #7
        bne @nct
        lda #HUD_COMBO
        ora hud_dirty
        sta hud_dirty
@nct:   rts

; Marks the lit cell Y for the colour pass (X kept).
lmark:
        stx lm_x
        tya
        tax
        jsr color_mark
        ldx lm_x
        rts

.segment "BSS"
lm_x:       .res 1
.segment "CODE"

; The effects of the game event X (draw.ts event()).
render_event:
        lda ev_type, x
        cmp #EV_SONG_START
        bne @n1
        jmp render_reset
@n1:    cmp #EV_FLEE
        bne @n2
        ldy ev_index, x
        lda #FLEE_TICKS
        sta flee_mark, y
        rts
@n2:    cmp #EV_CRASH
        bne @n3
        lda #SHAKE_TICKS
        sta shake
        lda #FLASH_TICKS
        sta screen_flash
        lda #2 * TICK_HZ
        sta lives_flash
        rts
@n3:    cmp #EV_EXTRA_LIFE
        bne @n4
        lda #2 * TICK_HZ
        sta lives_flash
        rts
@n4:    cmp #EV_CATCH
        bne @n5
        lda ev_count, x
        cmp #2
        bcc @n5
        lda #30
        sta combo_flash
        rts
@n5:    cmp #EV_CLEARED
        bne @n6
        lda #1
        sta cleared_ticks
        lda #4
        sta full_q
@n6:    rts

; ---------------------------------------------------------------- a frame

; Draws the changes of the field for this frame.
render_field:
        lda field_on
        beq @off
        jsr place_objects
        jsr color_pass
        jsr update_leds
        jsr update_desk
        ; the screen shake moves the bitmap rows
        lda shake
        beq @s
        lda r_ticks
        and #7
        sta shake_x
        lda #1
        sta rows_dirty
        rts
@s:     lda shake_x
        beq @off
        lda #0
        sta shake_x
        lda #1
        sta rows_dirty
@off:   rts
