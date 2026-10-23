; fx.s - the hardware sprites of a game: the DJ behind the desk (sprite 0) and the
; effects of draw.ts in sprites 1..7: floating texts (+points, X combo, STAR!,
; EXTRA LIFE!), confetti bursts, the sparkles of a star, the dizzy stars of a crash,
; the "!" over fleeing shy guests and the waiting hint over the leader.
;
; The effects draw into their own sprite images (SPRDYN); each frame the visible
; ones are given hardware sprites in the order of their importance.

; images in SPRDYN
IMG_TEXT    = 0             ; 3 texts of 2 images each: 0..5
IMG_BURST   = 6             ; 2 bursts: 6, 7
IMG_SPARK   = 8
IMG_DIZZY   = 9
IMG_FLEE    = 10
IMG_WAIT    = 11            ; 3 images: 11..13
IMG_SWEAT   = 14

TEXTS = 3
BURSTS = 2
PARTS = 16                  ; particles per burst

.segment "BSS"
; floating texts
tx_life:    .res TEXTS
tx_x:       .res TEXTS      ; screen x of the centre (0..255, + 8 = pixel)
tx_y:       .res TEXTS      ; 8.8 screen y of the top
tx_yf:      .res TEXTS
tx_vy:      .res TEXTS      ; rise in 1/256 pixels per tick
tx_col:     .res TEXTS
tx_n:       .res TEXTS      ; images (1 or 2)
tx_big:     .res TEXTS      ; expanded
tx_next:    .res 1
; bursts
bu_life:    .res BURSTS     ; ticks left of the longest particle
bu_x:       .res BURSTS     ; screen x / y of the origin
bu_y:       .res BURSTS
bu_col:     .res BURSTS
bu_next:    .res 1
pa_x:       .res BURSTS * PARTS     ; 8.8 relative position
pa_xf:      .res BURSTS * PARTS
pa_y:       .res BURSTS * PARTS
pa_yf:      .res BURSTS * PARTS
pa_vx:      .res BURSTS * PARTS
pa_vxf:     .res BURSTS * PARTS
pa_vy:      .res BURSTS * PARTS
pa_vyf:     .res BURSTS * PARTS
pa_life:    .res BURSTS * PARTS
dj_on:      .res 1
dj_x:       .res 1
dj_y:       .res 1
wait_lang:  .res 1          ; the language of the waiting hint images ($ff: none)
; the hardware sprites of this frame
hw_n:       .res 1
fx_t:       .res 4
fx_i:       .res 1
fx_k:       .res 1
fx_cell:    .res 1

.segment "RODATA"
mini_font:  .incbin "mini.bin"
combo_color: .byte WHITE, WHITE, CYAN, LRED, YELLOW, LGREEN
; screen x / 2 and y (pixels, the field starts at 8 / 8) of the top left of each cell
cell_px2:
.repeat CELLS, i
        .byte 4 + (i .mod COLS) * 8
.endrepeat
cell_py:
.repeat CELLS, i
        .byte 8 + (i / COLS) * 16
.endrepeat
.segment "CODE"

; ---------------------------------------------------------------- setup

fx_reset:
        ldx #TEXTS - 1
        lda #0
@t:     sta tx_life, x
        dex
        bpl @t
        ldx #BURSTS - 1
@b:     sta bu_life, x
        dex
        bpl @b
        sta tx_next
        sta bu_next
        sta spr_en
        lda #$ff
        sta wait_lang
        ; the "!" image
        ldx #63
        lda #0
@c:     sta SPRDYN + IMG_FLEE * 64, x
        dex
        bpl @c
        lda #$c0
        sta SPRDYN + IMG_FLEE * 64
        sta SPRDYN + IMG_FLEE * 64 + 3
        sta SPRDYN + IMG_FLEE * 64 + 6
        sta SPRDYN + IMG_FLEE * 64 + 9
        sta SPRDYN + IMG_FLEE * 64 + 15
        ; the drop of sweat
        ldx #63
        lda #0
@cs:    sta SPRDYN + IMG_SWEAT * 64, x
        dex
        bpl @cs
        lda #$80
        sta SPRDYN + IMG_SWEAT * 64
        sta SPRDYN + IMG_SWEAT * 64 + 3
        rts

; The DJ stands behind the middle of the desk (the cell with run index 2).
place_dj:
        lda #0
        sta dj_on
        ldx #0
@c:     lda tile, x
        cmp #TILE_DJ
        bne @n
        lda b_run, x
        cmp #2
        bne @n
        lda cell_px2, x
        asl
        clc
        adc #24 - 4
        sta dj_x
        lda cell_py, x
        clc
        adc #50 - 5 - 4
        sta dj_y
        lda #1
        sta dj_on
        rts
@n:     inx
        cpx #CELLS
        bne @c
        rts

; ---------------------------------------------------------------- texts

; Writes the mini font text (codes in tbuf, tlen) centred into the images A, A + 1
; (2 images if longer than 6 characters), lines at row Y. Returns the images in X.
draw_mini:
        sta dm_img
        sty dm_row
        ldx #1
        lda tlen
        cmp #7
        bcc @one
        inx
@one:   stx dm_n
        ; clear the images
        lda dm_img
        jsr img_ptr
        ldy #127
        lda #0
@cl:    sta (dst), y
        dey
        bpl @cl
        ; x of the first column: (24 * n - 4 * len) / 2
        lda dm_n
        asl
        asl
        asl
        sta fx_t
        asl
        adc fx_t                ; 24 * n
        sta fx_t
        lda tlen
        asl
        asl
        sta fx_t + 1
        lda fx_t
        sec
        sbc fx_t + 1
        lsr
        and #$fc
        sta dm_x
        jsr mini_line
        ldx dm_n
        rts

; Draws tbuf / tlen from pixel dm_x on.
mini_line:
        ldx #0
@ch:    cpx tlen
        beq @done
        stx dm_i
        lda tbuf, x
        jsr mini_char
        lda dm_x
        clc
        adc #4
        sta dm_x
        ldx dm_i
        inx
        bne @ch
@done:  rts

.segment "BSS"
dm_img:     .res 1
dm_row:     .res 1
dm_n:       .res 1
dm_x:       .res 1
dm_i:       .res 1
dm_g:       .res 1
.segment "CODE"

; dst = the image A.
img_ptr:
        ldx #0
        stx dst + 1
        asl
        asl
        rol dst + 1
        asl
        rol dst + 1
        asl
        rol dst + 1
        asl
        rol dst + 1
        asl
        rol dst + 1
        sta dst
        lda dst + 1
        clc
        adc #>SPRDYN
        sta dst + 1
        rts

; Draws the mini font character A (3x5) at pixel dm_x (a multiple of 4), row dm_row
; of the images at dst.
mini_char:
        sta dm_g
        asl
        asl
        adc dm_g                ; * 5
        tax
        lda #0
        sta fx_k
@row:   lda mini_font, x
        beq @next
        sta mc_g
        lda dm_x
        ldy #0
@img:   cmp #24
        bcc @in
        sbc #24
        iny
        bne @img
@in:    sta mc_xi
        tya
        asl
        asl
        asl
        asl
        asl
        asl
        sta mc_off              ; image * 64
        lda dm_row
        clc
        adc fx_k
        sta mc_r
        asl
        adc mc_r
        adc mc_off
        sta mc_off
        lda mc_xi
        lsr
        lsr
        lsr
        clc
        adc mc_off
        tay
        lda mc_xi
        and #4
        beq @ns
        lda mc_g
        lsr
        lsr
        lsr
        lsr
        bne @put
@ns:    lda mc_g
@put:   ora (dst), y
        sta (dst), y
@next:  inx
        inc fx_k
        lda fx_k
        cmp #5
        bne @row
        rts

.segment "BSS"
mc_g:       .res 1
mc_xi:      .res 1
mc_off:     .res 1
mc_r:       .res 1
.segment "CODE"

; Starts a floating text: tbuf / tlen (mini font codes), at the screen centre x A,
; top y Y, colour fx_t + 0 (set fxs_col), expanded if fxs_big.
add_text:
        ldx #0
        stx tlen2
        ldx #0
        beq at_row
add_text_row7:
        ldx #7
at_row: stx fxs_row
        sta fxs_x
        sty fxs_y
        ldx tx_next
        inx
        cpx #TEXTS
        bcc @s
        ldx #0
@s:     stx tx_next
        stx fx_i
        txa
        asl                     ; images 2 i, 2 i + 1
        ldy fxs_row
        jsr draw_mini
        txa
        ldx fx_i
        sta tx_n, x
        lda fxs_x
        sta tx_x, x
        lda fxs_y
        sta tx_y, x
        lda #0
        sta tx_yf, x
        lda fxs_vy
        sta tx_vy, x
        lda fxs_col
        sta tx_col, x
        lda fxs_big
        sta tx_big, x
        lda fxs_life
        sta tx_life, x
        rts

.segment "BSS"
fxs_x:      .res 1
fxs_y:      .res 1
fxs_vy:     .res 1
fxs_col:    .res 1
fxs_big:    .res 1
fxs_life:   .res 1
fxs_row:    .res 1
.segment "CODE"

; The mini font text A (T_MINI_*) of the current language into tbuf / tlen.
mini_text:
        jmp expand

; Appends the number num as mini font digits.
mini_num:
        lda tlen
        sta fx_t
        jsr append_num
        ; the text font digits to mini font digits
        ldx fx_t
@l:     cpx tlen
        beq @r
        lda tbuf, x
        sec
        sbc #C_ZERO
        clc
        adc #M_ZERO
        sta tbuf, x
        inx
        bne @l
@r:     rts

; ---------------------------------------------------------------- bursts

; A burst of fxb_n confetti particles at cell A (gold if fxb_gold).
add_burst:
        tax
        lda cell_px2, x
        clc
        adc #4
        sta fxs_x
        lda cell_py, x
        clc
        adc #6
        sta fxs_y
        ldx bu_next
        inx
        cpx #BURSTS
        bcc @s
        ldx #0
@s:     stx bu_next
        lda fxs_x
        sta bu_x, x
        lda fxs_y
        sta bu_y, x
        lda #CYAN
        ldy fxb_gold
        beq @c
        lda #YELLOW
@c:     sta bu_col, x
        lda #28
        sta bu_life, x
        ; particles: angle a = k * 2.39996 + ticks * 0.3 (in 64ths: 24.4 k + 3 t)
        txa
        asl
        asl
        asl
        asl
        sta ab_p                ; first particle
        lda #0
        sta ab_k
@p:     ldx ab_p
        lda ab_k
        cmp fxb_n
        bcc @live
        lda #0
        sta pa_life, x
        beq @np
@live:  ; life 20 + k % 8
        and #7
        clc
        adc #20
        sta pa_life, x
        lda #0
        sta pa_x, x
        sta pa_xf, x
        sta pa_y, x
        sta pa_yf, x
        ; table index: (k % 4) * 64 + angle
        lda ab_k
        asl
        asl
        asl
        asl
        asl
        sta fx_t                ; k * 32 (lo)
        lda ab_k
        lsr
        lsr
        lsr
        clc
        adc fx_t
        sbc ab_k                ; ~ k * 24.4 (close enough)
        sta fx_t
        lda r_ticks
        asl
        adc r_ticks
        adc fx_t
        and #63
        sta fx_t
        lda ab_k
        and #3
        asl
        asl
        asl
        asl
        asl
        asl
        ora fx_t
        tay
        lda conf_vx_lo, y
        sta pa_vxf, x
        lda conf_vx_hi, y
        sta pa_vx, x
        lda conf_vy_lo, y
        sta pa_vyf, x
        lda conf_vy_hi, y
        sta pa_vy, x
@np:    inc ab_p
        inc ab_k
        lda ab_k
        cmp #PARTS
        beq *+5
        jmp @p
        rts

.segment "BSS"
ab_p:       .res 1
ab_k:       .res 1
fxb_n:      .res 1
fxb_gold:   .res 1
.segment "CODE"

; Moves the particles of burst X and draws them into its image.
burst_tick:
        stx fx_cell
        lda bu_life, x
        bne @go
        rts
@go:    dec bu_life, x
        txa
        clc
        adc #IMG_BURST
        jsr img_ptr
        ldy #62
        lda #0
@cl:    sta (dst), y
        dey
        bpl @cl
        lda fx_cell
        asl
        asl
        asl
        asl
        tax
        lda #PARTS
        sta fx_k
@p:     lda pa_life, x
        bne *+5
        jmp @next
        dec pa_life, x
        bne *+5
        jmp @next
        ; move, then gravity 0.04 (10 / 256)
        clc
        lda pa_xf, x
        adc pa_vxf, x
        sta pa_xf, x
        lda pa_x, x
        adc pa_vx, x
        sta pa_x, x
        clc
        lda pa_yf, x
        adc pa_vyf, x
        sta pa_yf, x
        lda pa_y, x
        adc pa_vy, x
        sta pa_y, x
        clc
        lda pa_vyf, x
        adc #10
        sta pa_vyf, x
        bcc @g
        inc pa_vy, x
@g:     ; plot: column (x + 24) / 4 (0..11), row (y + 21) / 2 (0..20)
        lda pa_x, x
        clc
        adc #24
        cmp #48
        bcs @next
        lsr
        lsr
        sta fx_t
        lda pa_y, x
        clc
        adc #21
        cmp #42
        bcs @next
        lsr
        sta fx_t + 1
        asl
        adc fx_t + 1
        sta fx_t + 1            ; row * 3
        lda fx_t
        lsr
        lsr
        clc
        adc fx_t + 1
        tay
        lda fx_t
        and #3
        stx fx_t + 2
        tax
        ; the colour: 10 (own) or 11 (pink) by particle
        lda fx_k
        and #1
        beq @c10
        lda mc_mask11, x
        bne @put
@c10:   lda mc_mask10, x
@put:   ora (dst), y
        sta (dst), y
        ldx fx_t + 2
@next:  inx
        dec fx_k
        beq *+5
        jmp @p
        rts

.segment "RODATA"
mc_mask10:  .byte $80, $20, $08, $02
mc_mask11:  .byte $c0, $30, $0c, $03
.segment "CODE"

; ---------------------------------------------------------------- events

; The effects of the game event X.
fx_event:
        stx fx_i
        lda ev_type, x
        cmp #EV_CATCH
        beq *+5
        jmp @n1
        ; confetti and the points floating up
        lda #10
        sta fxb_n
        lda #0
        sta fxb_gold
        ldy ev_index, x
        cpy #GUEST_STAR
        bne @b
        lda #16
        sta fxb_n
        lda #1
        sta fxb_gold
@b:     lda ev_cell, x
        jsr add_burst
        ldx fx_i
        ; colour by the combo, gold for a star
        ldy ev_count, x
        cpy #6
        bcc @cc
        ldy #5
@cc:    lda combo_color, y
        ldy ev_index, x
        cpy #GUEST_STAR
        bne @cs
        lda #YELLOW
@cs:    sta fxs_col
        ; large for a combo of 3 and more or a star
        lda #0
        ldy ev_count, x
        cpy #3
        bcs @big
        ldy ev_index, x
        cpy #GUEST_STAR
        bne @sm
@big:   lda #1
@sm:    sta fxs_big
        ; the text: "X n" in the first line (from 2), "+points" in the second
        lda #0
        sta tlen
        lda ev_count, x
        cmp #2
        bcc @nx
        lda #M_X
        sta tbuf
        lda #1
        sta tlen
        lda ev_count, x
        sta num
        lda #0
        sta num + 1
        sta num + 2
        jsr mini_num
@nx:    ldx tlen
        stx tlen2
@cp:    dex
        bmi @cpd
        lda tbuf, x
        sta tbuf2, x
        jmp @cp
@cpd:   lda #M_PLUS
        sta tbuf
        lda #1
        sta tlen
        lda fx_i
        asl
        tay
        lda ev_points, y
        sta num
        lda ev_points + 1, y
        sta num + 1
        lda #0
        sta num + 2
        jsr mini_num
        ldx tlen
        lda #M_ZERO
        sta tbuf, x
        sta tbuf + 1, x
        inx
        inx
        stx tlen
        lda #TICK_HZ
        sta fxs_life
        lda #77
        sta fxs_vy
        ldx fx_i
        ldy ev_cell, x
        lda cell_px2, y
        clc
        adc #4
        pha
        lda cell_py, y
        sec
        sbc #10
        tay
        pla
        jmp add_text2
@n1:    cmp #EV_STAR
        bne @n2
        lda #12
        sta fxb_n
        lda #1
        sta fxb_gold
        lda ev_cell, x
        jsr add_burst
        lda #T_MINI_STAR
        jsr mini_text
        lda #YELLOW
        sta fxs_col
        lda #0
        sta fxs_big
        lda #TICK_HZ
        sta fxs_life
        lda #51
        sta fxs_vy
        ldx fx_i
        ldy ev_cell, x
        lda cell_px2, y
        clc
        adc #4
        pha
        lda cell_py, y
        sec
        sbc #14
        tay
        pla
        jmp add_text
@n2:    cmp #EV_STAR_GONE
        bne @n3
        lda #6
        sta fxb_n
        lda #1
        sta fxb_gold
        lda ev_cell, x
        jmp add_burst
@n3:    cmp #EV_EXTRA_LIFE
        bne @n4
        lda #T_MINI_EXTRALIFE
        jsr mini_text
        lda #LGREEN
        sta fxs_col
        lda #1
        sta fxs_big
        lda #2 * TICK_HZ
        sta fxs_life
        lda #38
        sta fxs_vy
        lda #80
        ldy #90
        jmp add_text
@n4:    cmp #EV_CLEARED
        bne @n5
        ; confetti at the leader and the end of the line
        lda #6
        sta fxb_n
        lda #0
        sta fxb_gold
        lda body
        jsr add_burst
        ldy length
        lda body - 1, y
        jmp add_burst
@n5:    rts

; Like add_text with two lines: tbuf in row 7, tbuf2 / tlen2 (if any) in row 0.
; A = centre x, Y = top y.
add_text2:
        jsr add_text_row7
        lda tlen2
        beq @r
        ldx fx_i
        txa
        asl
        jsr img_ptr
        ldy tlen2
        sty tlen
@cp:    dey
        bmi @cpd
        lda tbuf2, y
        sta tbuf, y
        jmp @cp
@cpd:   lda #0
        sta dm_row
        ; centred in 24 * n pixels
        ldx fx_i
        lda tx_n, x
        asl
        asl
        asl
        sta fx_t
        asl
        adc fx_t
        sta fx_t
        lda tlen
        asl
        asl
        sta fx_t + 1
        lda fx_t
        sec
        sbc fx_t + 1
        lsr
        and #$fc
        sta dm_x
        jmp mini_line
@r:     rts

.segment "BSS"
tbuf2:      .res 16
tlen2:      .res 1
.segment "CODE"

; ---------------------------------------------------------------- ticks

; Advances the effects by one tick.
fx_tick:
        ldx #TEXTS - 1
@t:     lda tx_life, x
        beq @nt
        dec tx_life, x
        lda tx_yf, x
        sec
        sbc tx_vy, x
        sta tx_yf, x
        bcs @nt
        dec tx_y, x
@nt:    dex
        bpl @t
        ldx #0
        jsr burst_tick
        ldx #1
        jmp burst_tick

; ---------------------------------------------------------------- the sprites of a frame

; Adds a hardware sprite: image A (in SPRDYN), x fs_x (0..255 + 8 if fs_xhi), y fs_y,
; colour fs_col, flags fs_fl (bit 0 multicolor, bit 1 expanded).
hw_add:
        ldx hw_n
        cpx #8
        bcs @full
        clc
        adc #SPRDYN_PTR
        sta spr_ptr, x
        lda fs_x
        sta spr_x, x
        lda fs_xhi
        sta spr_xhi, x
        lda fs_y
        sta spr_y, x
        lda fs_col
        sta spr_col, x
        lda bit_tab, x
        ora spr_en
        sta spr_en
        lda fs_fl
        lsr
        bcc @nm
        lda bit_tab, x
        ora spr_mc
        sta spr_mc
@nm:    lda fs_fl
        and #2
        beq @ne
        lda bit_tab, x
        ora spr_xe
        sta spr_xe
        lda bit_tab, x
        ora spr_ye
        sta spr_ye
@ne:    inc hw_n
@full:  rts

.segment "BSS"
fs_x:       .res 1
fs_xhi:     .res 1
fs_y:       .res 1
fs_col:     .res 1
fs_fl:      .res 1
.segment "RODATA"
bit_tab:    .byte 1, 2, 4, 8, 16, 32, 64, 128
.segment "CODE"

; Sets fs_x / fs_xhi from the screen x / 2 in A: 2 A + 24 + X (X signed).
sprite_x:
        stx fx_t
        asl
        sta fs_x
        lda #0
        rol
        sta fs_xhi
        lda fs_x
        clc
        adc #24
        sta fs_x
        bcc @a
        inc fs_xhi
@a:     lda fx_t
        bmi @neg
        clc
        adc fs_x
        sta fs_x
        bcc @r
        inc fs_xhi
@r:     rts
@neg:   clc
        adc fs_x
        sta fs_x
        bcs @r
        dec fs_xhi
        rts

; Carry set if screen y A (the middle of a sprite) is over a panel (a text row).
over_panel:
        lsr
        lsr
        lsr
        cmp #25
        bcs @yes
        tax
        lda rowmode, x
        bne @yes
        clc
        rts
@yes:   sec
        rts

; The sprites of this frame.
fx_draw:
        lda #0
        sta hw_n
        sta spr_en
        sta spr_mc
        sta spr_xe
        sta spr_ye
        sta spr_pri
        lda #BLACK
        sta spr_mc1
        lda #LRED
        sta spr_mc2
        ; the DJ dances: arms up on every other beat, a hop at the beat
        lda dj_on
        beq @nodj
        lda r_b2
        clc
        adc #SPRSTAT_PTR + SPR_DJ0
        sta spr_ptr
        lda dj_x
        sta spr_x
        lda #0
        sta spr_xhi
        lda dj_y
        ldx r_bphase
        cpx #6
        bcs @h
        sec
        sbc #1
@h:     sta spr_y
        lda #PURPLE
        sta spr_col
        lda #1
        sta spr_en
        sta spr_mc
@nodj:  lda #1
        sta hw_n
        jsr waiting_sprites
        jsr text_sprites
        jsr burst_sprites
        jsr dizzy_sprite
        jsr spark_sprite
        jsr flee_sprites
        jmp sweat_sprites

; The waiting hint over (or under) the leader: blinks 2 of 3 times 20 ticks.
waiting_sprites:
        lda phase
        cmp #PHASE_PLAY
        beq *+5
        jmp @r
        lda moving
        beq *+5
        jmp @r
        lda panel_cur
        beq *+5
        jmp @r
        lda r_t20
        ldx #3
        jsr mod_small
        cmp #2
        beq @r
        ; the images of the current language
        lda lang
        cmp wait_lang
        beq @have
        sta wait_lang
        lda #T_MINI_WAITING
        jsr mini_text
        ; 3 images: draw as two halves of up to 6 + the rest
        jsr draw_wait
@have:  ; y: 29 above the cell centre, or 22 below in the top rows
        ldx body
        lda cell_py, x
        sec
        sbc #23
        ldy cell_y, x
        cpy #2
        bcs @y
        lda cell_py, x
        clc
        adc #28
@y:     clc
        adc #50
        sta fs_y
        ; x / 2: centred, kept on the screen (0..124)
        lda cell_px2, x
        sec
        sbc #14
        bcs @x0
        lda #0
@x0:    cmp #124
        bcc @xx
        lda #124
@xx:    sta wt_x
        lda #YELLOW
        sta fs_col
        lda #0
        sta fs_fl
        sta wt_i
@s:     lda wt_i
        asl
        asl
        sta fx_t + 3
        asl
        adc fx_t + 3            ; 12 i
        adc wt_x
        ldx #0
        jsr sprite_x
        lda wt_i
        clc
        adc #IMG_WAIT
        jsr hw_add
        inc wt_i
        lda wt_i
        cmp #3
        bne @s
@r:     rts

.segment "BSS"
wt_x:       .res 1
wt_i:       .res 1
.segment "CODE"

; Draws the waiting hint (tbuf) into the images IMG_WAIT.. (3 images, 72 pixels).
draw_wait:
        lda #IMG_WAIT
        jsr img_ptr
        ldy #0
        lda #0
@cl:    sta (dst), y
        iny
        cpy #192
        bne @cl
        lda #3
        sta dm_n
        lda #0
        sta dm_row
        ; centred in 72 pixels
        lda tlen
        asl
        asl
        sta fx_t
        lda #72
        sec
        sbc fx_t
        lsr
        and #$fc
        sta dm_x
        jmp mini_line

; A = A % X (small numbers).
mod_small:
        stx fx_t
@l:     cmp fx_t
        bcc @r
        sbc fx_t
        bcs @l
@r:     rts

text_sprites:
        lda #0
        sta fx_i
@t:     ldx fx_i
        lda tx_life, x
        bne *+5
        jmp @next
        lda tx_y, x
        clc
        adc #6
        jsr over_panel
        bcs @next
        ldx fx_i
        lda tx_y, x
        clc
        adc #50
        sta fs_y
        ; the colour fades at the end
        lda tx_col, x
        ldy tx_life, x
        cpy #12
        bcs @c
        lda #DGREY
        cpy #6
        bcs @c
        lda #BLUE
@c:     sta fs_col
        lda tx_big, x
        asl
        sta fs_fl
        ; left / 2: centre / 2 - 6 n (* 2 when expanded)
        lda tx_n, x
        asl
        asl
        sta fx_t
        lsr
        adc fx_t                ; 6 n
        ldy tx_big, x
        beq @w
        asl
@w:     sta fx_t + 1
        lda tx_x, x
        sec
        sbc fx_t + 1
        bcs @xo
        lda #0
@xo:    ldx #0
        jsr sprite_x
        ldx fx_i
        txa
        asl
        jsr hw_add
        ldx fx_i
        lda tx_n, x
        cmp #2
        bcc @next
        ; the second image right of it
        lda fs_x
        clc
        adc #24
        ldy tx_big, x
        beq @w2
        adc #24
@w2:    sta fs_x
        bcc @x2
        inc fs_xhi
@x2:    lda fx_i
        asl
        clc
        adc #1
        jsr hw_add
@next:  inc fx_i
        lda fx_i
        cmp #TEXTS
        beq *+5
        jmp @t
        rts

burst_sprites:
        lda #0
        sta fx_i
@b:     ldx fx_i
        lda bu_life, x
        beq @next
        lda bu_y, x
        jsr over_panel
        bcs @next
        ldx fx_i
        lda bu_y, x
        clc
        adc #50 - 21
        sta fs_y
        lda bu_x, x
        sec
        sbc #12
        bcs @x
        lda #0
@x:     ldx #0
        jsr sprite_x
        ldx fx_i
        lda bu_col, x
        sta fs_col
        lda #3
        sta fs_fl
        txa
        clc
        adc #IMG_BURST
        jsr hw_add
@next:  inc fx_i
        lda fx_i
        cmp #BURSTS
        bne @b
        rts

; Three stars circle over the head of the leader while the crash lasts.
dizzy_sprite:
        lda phase
        cmp #PHASE_CRASH
        bne @r
        lda panel_cur
        bne @r
        lda #IMG_DIZZY
        jsr img_ptr
        ldy #62
        lda #0
@cl:    sta (dst), y
        dey
        bpl @cl
        ; angle: ticks * 0.15 + k * 2.1 (in 64ths: 1.5 t + 21.4 k), centre (11, 8)
        lda r_ticks
        lsr
        adc r_ticks
        sta fx_t + 3
        lda #3
        sta fx_k
@k:     lda fx_t + 3
        and #63
        tax
        lda dizzy_dx, x
        clc
        adc #11
        sta fx_t
        lda dizzy_dy, x
        clc
        adc #8
        sta fx_t + 1
        jsr plot2
        lda fx_t + 3
        clc
        adc #21
        sta fx_t + 3
        dec fx_k
        bne @k
        ldx body
        lda cell_px2, x
        ldx #$fc
        jsr sprite_x
        ldx body
        lda cell_py, x
        clc
        adc #50 - 4 - 8
        sta fs_y
        lda #YELLOW
        sta fs_col
        lda #0
        sta fs_fl
        lda #IMG_DIZZY
        jmp hw_add
@r:     rts

; Four sparkles circle around a star guest.
spark_sprite:
        ldx #MAX_GUESTS - 1
@g:     lda g_active, x
        beq @n
        lda g_type, x
        cmp #GUEST_STAR
        beq @star
@n:     dex
        bpl @g
        rts
@star:  ldy g_cell, x
        sty fx_cell
        lda cell_py, y
        clc
        adc #6
        jsr over_panel
        bcs @r
        lda #IMG_SPARK
        jsr img_ptr
        ldy #62
        lda #0
@cl:    sta (dst), y
        dey
        bpl @cl
        lda r_ticks
        sta fx_t + 3
        lda #4
        sta fx_k
@k:     lda fx_t + 3
        and #63
        tax
        lda spark_dx, x
        clc
        adc #11
        sta fx_t
        lda spark_dy, x
        clc
        adc #10
        sta fx_t + 1
        jsr plot2
        lda fx_t + 3
        clc
        adc #16
        sta fx_t + 3
        dec fx_k
        bne @k
        ldx fx_cell
        lda cell_px2, x
        ldx #$fc
        jsr sprite_x
        ldx fx_cell
        lda cell_py, x
        clc
        adc #50 - 4
        sta fs_y
        lda #YELLOW
        ldx r_t8
        txa
        and #1
        beq @c
        lda #WHITE
        bne @c2
@c:     lda #YELLOW
@c2:    sta fs_col
        lda #0
        sta fs_fl
        lda #IMG_SPARK
        jmp hw_add
@r:     rts

; Plots a 2x2 dot at fx_t, fx_t + 1 (0..22, 0..19) into the hires image at dst.
plot2:
        lda fx_t + 1
        cmp #20
        bcs @r
        sta fx_t + 2
        asl
        adc fx_t + 2
        sta fx_t + 2            ; row * 3
        lda fx_t
        cmp #23
        bcs @r
        lsr
        lsr
        lsr
        clc
        adc fx_t + 2
        tay
        lda fx_t
        and #7
        tax
        lda dot_mask, x
        ora (dst), y
        sta (dst), y
        lda dot_mask2, x
        beq @n
        iny
        ora (dst), y
        sta (dst), y
        dey
@n:     tya
        clc
        adc #3
        tay
        lda dot_mask, x
        ora (dst), y
        sta (dst), y
        lda dot_mask2, x
        beq @r
        iny
        ora (dst), y
        sta (dst), y
@r:     rts

.segment "RODATA"
dot_mask:   .byte $c0, $60, $30, $18, $0c, $06, $03, $01
dot_mask2:  .byte 0, 0, 0, 0, 0, 0, 0, $80
.segment "CODE"

; "!" over the shy guests that just fled.
flee_sprites:
        ldx #0
@g:     stx fx_i
        lda flee_mark, x
        beq @n
        lda g_active, x
        beq @n
        ldy g_cell, x
        sty fx_cell
        lda cell_py, y
        jsr over_panel
        bcs @n
        ldx fx_cell
        lda cell_px2, x
        ldx #13
        jsr sprite_x
        ldx fx_cell
        lda cell_py, x
        clc
        adc #50 - 9
        sta fs_y
        lda #YELLOW
        sta fs_col
        lda #0
        sta fs_fl
        lda #IMG_FLEE
        jsr hw_add
@n:     ldx fx_i
        inx
        cpx g_top
        bcc @g
        rts

; Nervous shy guests sweat: a cyan drop now and then ((ticks / 20 + slot) % 3 == 0).
sweat_sprites:
        ldx #0
@g:     stx fx_i
        cpx g_top
        bcs @r
        lda g_active, x
        beq @n
        lda g_type, x
        cmp #GUEST_SHY
        bne @n
        lda flee_mark, x
        bne @n
        txa
        clc
        adc r_t20
        ldx #3
        jsr mod_small
        cmp #0
        bne @n
        ldx fx_i
        ldy g_cell, x
        sty fx_cell
        lda cell_py, y
        jsr over_panel
        bcs @n
        ldx fx_cell
        lda cell_px2, x
        ldx #13
        jsr sprite_x
        ldx fx_cell
        lda cell_py, x
        clc
        adc #50 - 1
        sta fs_y
        lda #CYAN
        sta fs_col
        lda #0
        sta fs_fl
        lda #IMG_SWEAT
        jsr hw_add
@n:     ldx fx_i
        inx
        bne @g
@r:     rts
