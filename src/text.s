; text.s - texts in the character rows: the texts of the two languages with their
; placeholders, numbers, large letters (2x2 characters made from the font at
; runtime) and the frames of the info panels.

.segment "BSS"
lang:       .res 1          ; 0 German, 1 English
t_song:     .res 2          ; the values of the placeholders
t_target:   .res 2
t_count:    .res 2
t_rank:     .res 2
t_score:    .res 3          ; in units of 100 points
tbuf:       .res 48         ; the expanded text
tlen:       .res 1
t_row:      .res 1
t_col:      .res 1
t_color:    .res 1
bigmap:     .res 64         ; character -> first of its 4 large characters (0: none yet)
pool_next:  .res 1
num:        .res 3          ; number conversion
num_dig:    .res 1
tx_i:       .res 1
tx_j:       .res 1

.segment "RODATA"
.include "text.inc"

; powers of ten for 24 bit numbers
pow10_0:    .byte <1000000, <100000, <10000, <1000, <100, <10, <1
pow10_1:    .byte >1000000, >100000, >10000, >1000, >100, >10, >1
pow10_2:    .byte ^1000000, ^100000, ^10000, ^1000, ^100, ^10, ^1
; a nibble with each bit doubled
expand_nib: .byte $00, $03, $0c, $0f, $30, $33, $3c, $3f, $c0, $c3, $cc, $cf, $f0, $f3, $fc, $ff

.segment "CODE"

; ---------------------------------------------------------------- expanding

; Expands the text A of the current language into tbuf / tlen.
expand:
        ldx lang
        beq @de
        clc
        adc #TEXT_COUNT
@de:    tax
        lda text_ptr_lo, x
        sta ptr2
        lda text_ptr_hi, x
        sta ptr2 + 1
        lda #0
        sta tlen
        sta tx_i
@l:     ldy tx_i
        lda (ptr2), y
        cmp #$ff
        beq @done
        inc tx_i
        cmp #$f0
        bcs @ph
        ldx tlen
        sta tbuf, x
        inc tlen
        bne @l
@ph:    cmp #$f4
        beq @score
        and #$0f
        asl
        tax
        lda t_song, x
        sta num
        lda t_song + 1, x
        sta num + 1
        lda #0
        sta num + 2
        jsr append_num
        jmp @l
@score: jsr append_score
        jmp @l
@done:  rts

; Appends t_score (units of 100) as a number of points to tbuf.
append_score:
        lda t_score
        sta num
        lda t_score + 1
        sta num + 1
        lda t_score + 2
        sta num + 2
        ora num
        ora num + 1
        beq append_num          ; 0
        jsr append_num
        ldx tlen
        lda #C_ZERO
        sta tbuf, x
        sta tbuf + 1, x
        inx
        inx
        stx tlen
        rts

; Appends the 24 bit number num in decimal to tbuf.
append_num:
        lda #0
        sta num_dig             ; digits written (no leading zeros)
        ldx #0
@pow:   ldy #0
@sub:   lda num
        sec
        sbc pow10_0, x
        sta tx_j
        lda num + 1
        sbc pow10_1, x
        pha
        lda num + 2
        sbc pow10_2, x
        bcc @under
        sta num + 2
        pla
        sta num + 1
        lda tx_j
        sta num
        iny
        bne @sub
@under: pla
        tya
        bne @dig
        lda num_dig
        bne @dig
        cpx #6
        bne @next               ; leading zero
@dig:   tya
        clc
        adc #C_ZERO
        ldy tlen
        sta tbuf, y
        inc tlen
        inc num_dig
@next:  inx
        cpx #7
        bne @pow
        rts

; Puts the 16 bit number in A (lo) / X (hi) into tbuf (alone).
num_to_buf:
        sta num
        stx num + 1
        lda #0
        sta num + 2
        sta tlen
        jmp append_num

; ---------------------------------------------------------------- printing

; Prints tbuf at t_row / t_col in t_color.
print_buf:
        ldx t_row
        lda row_scr_lo, x
        clc
        adc t_col
        sta scr
        sta col
        lda row_scr_hi, x
        adc #>SCREEN
        sta scr + 1
        adc #>(COLRAM - SCREEN)
        sta col + 1
        ldy #0
@l:     cpy tlen
        beq @done
        lda tbuf, y
        sta (scr), y
        lda t_color
        sta (col), y
        iny
        bne @l
@done:  rts

; Prints the text A centred in row t_row.
print_center:
        jsr expand
center_buf:
        lda #40
        sec
        sbc tlen
        lsr
        sta t_col
        jmp print_buf

; Prints the text A at t_col (left aligned).
print_left:
        jsr expand
        jmp print_buf

; Prints the text A ending before t_col (right aligned).
print_right:
        jsr expand
right_buf:
        lda t_col
        sec
        sbc tlen
        sta t_col
        jmp print_buf

; Clears the character rows A..X (spaces in black).
clear_rows:
        sta cl_r
        stx cl_last
@r:     ldx cl_r
        lda row_scr_lo, x
        sta scr
        sta col
        lda row_scr_hi, x
        clc
        adc #>SCREEN
        sta scr + 1
        adc #>(COLRAM - SCREEN)
        sta col + 1
        ldy #39
@c:     lda #C_SPACE
        sta (scr), y
        lda #BLACK
        sta (col), y
        dey
        bpl @c
        lda cl_r
        cmp cl_last
        beq @done
        inc cl_r
        bne @r
@done:  rts

.segment "BSS"
cl_r:       .res 1
cl_last:    .res 1
.segment "CODE"

; Sets the colour A of the characters of row t_row from column t_col for tlen characters.
color_span:
        ldx t_row
        pha
        lda row_scr_lo, x
        clc
        adc t_col
        sta col
        lda row_scr_hi, x
        adc #>COLRAM
        sta col + 1
        pla
        ldy tlen
        beq @done
        dey
@l:     sta (col), y
        dey
        bpl @l
@done:  rts

; Draws a panel frame in colour A over the rows pf_top..pf_bottom (cleared first).
panel:
        sta pf_color
        lda pf_top
        ldx pf_bottom
        jsr clear_rows
        ldx pf_top
        lda #CH_TL
        ldy #CH_HZ
        jsr panel_row
        lda #CH_TR
        ldy #39
        jsr panel_put
        ldx pf_bottom
        lda #CH_BL
        ldy #CH_HZ
        jsr panel_row
        lda #CH_BR
        ldy #39
        jsr panel_put
        ldx pf_top
@side:  inx
        cpx pf_bottom
        beq @done
        lda #CH_VL
        ldy #0
        jsr panel_put
        lda #CH_VL
        ldy #39
        jsr panel_put
        jmp @side
@done:  rts

; Row X: the character A at column 0, Y in columns 1..38.
panel_row:
        sty pf_ch
        ldy #0
        jsr panel_put
        ldy #1
@l:     lda pf_ch
        jsr panel_put
        iny
        cpy #39
        bne @l
        rts

; Puts the character A at row X, column Y in the panel colour (X, Y kept).
panel_put:
        pha
        lda row_scr_lo, x
        sta scr
        sta col
        lda row_scr_hi, x
        clc
        adc #>SCREEN
        sta scr + 1
        adc #>(COLRAM - SCREEN)
        sta col + 1
        pla
        sta (scr), y
        lda pf_color
        sta (col), y
        rts

.segment "BSS"
pf_top:     .res 1
pf_bottom:  .res 1
pf_color:   .res 1
pf_ch:      .res 1
.segment "CODE"

; ---------------------------------------------------------------- large letters

; Forgets the large letters (a new screen).
big_reset:
        ldx #63
        lda #0
@l:     sta bigmap, x
        dex
        bpl @l
        lda #CH_FREE
        sta pool_next
        rts

; The first of the 4 large characters of character A (made on first use); carry set if
; the pool is full.
big_char:
        tax
        lda bigmap, x
        beq @new
        clc
        rts
@new:   stx bc_ch
        lda pool_next
        cmp #128 - 3
        bcc @ok
        cmp #CH_POOL
        bcs @ok2
        lda #CH_POOL
@ok2:   cmp #256 - 3
        bcc @ok
        sec
        rts
@ok:    sta bc_code
        clc
        adc #4
        sta pool_next
        ldx bc_ch
        lda bc_code
        sta bigmap, x
        ; the glyph: CHARSET + ch * 8
        lda bc_ch
        ldy #0
        sty src + 1
        asl
        asl
        rol src + 1
        asl
        rol src + 1
        adc #<CHARSET
        sta src
        lda src + 1
        adc #>CHARSET
        sta src + 1
        ; target: CHARSET + code * 8
        lda bc_code
        ldy #0
        sty dst + 1
        asl
        rol dst + 1
        asl
        rol dst + 1
        asl
        rol dst + 1
        adc #<CHARSET
        sta dst
        lda dst + 1
        adc #>CHARSET
        sta dst + 1
        ; quadrants: 0 top left, 1 top right, 2 bottom left, 3 bottom right
        lda #0
        sta bc_q
@quad:  lda bc_q
        and #2
        asl                     ; first source row: 0 or 4
        sta bc_srow
        ldx #0                  ; target row
@row:   txa
        lsr
        clc
        adc bc_srow
        tay
        lda (src), y
        ldy bc_q
        cpy #1
        beq @lo
        cpy #3
        beq @lo
        lsr
        lsr
        lsr
        lsr
        jmp @hi
@lo:    and #$0f
@hi:    tay
        lda expand_nib, y
        stx bc_x
        pha
        lda bc_q
        asl
        asl
        asl
        clc
        adc bc_x
        tay
        pla
        sta (dst), y
        ldx bc_x
        inx
        cpx #8
        bne @row
        inc bc_q
        lda bc_q
        cmp #4
        bne @quad
        lda bc_code
        clc
        rts

.segment "BSS"
bc_ch:      .res 1
bc_code:    .res 1
bc_q:       .res 1
bc_srow:    .res 1
bc_x:       .res 1
.segment "CODE"

; Prints tbuf in large letters (2x2 characters) centred in rows t_row, t_row + 1.
print_big_buf:
        lda tlen
        asl
        sta bp_w
        lda #40
        sec
        sbc bp_w
        lsr
        sta t_col
        ldx t_row
        lda row_scr_lo, x
        clc
        adc t_col
        sta bp_scr
        lda row_scr_hi, x
        adc #>SCREEN
        sta bp_scr + 1
        lda #0
        sta tx_i
@l:     lda bp_scr
        sta scr
        sta col
        lda bp_scr + 1
        sta scr + 1
        clc
        adc #>(COLRAM - SCREEN)
        sta col + 1
        ldx tx_i
        cpx tlen
        beq @done
        lda tbuf, x
        beq @space
        jsr big_char
        bcc @put
@space: lda #C_SPACE
        ldy #0
        sta (scr), y
        iny
        sta (scr), y
        ldy #40
        sta (scr), y
        iny
        sta (scr), y
        jmp @col
@put:   ldy #0
        sta (scr), y
        clc
        adc #1
        iny
        sta (scr), y
        adc #1
        ldy #40
        sta (scr), y
        adc #1
        iny
        sta (scr), y
@col:   lda t_color
        ldy #0
        sta (col), y
        iny
        sta (col), y
        ldy #40
        sta (col), y
        iny
        sta (col), y
        lda bp_scr
        clc
        adc #2
        sta bp_scr
        bcc @n
        inc bp_scr + 1
@n:     inc tx_i
        bne @l
@done:  rts

; Prints the text A in large letters centred in rows t_row, t_row + 1.
print_big:
        jsr expand
        jmp print_big_buf

.segment "BSS"
bp_w:       .res 1
bp_scr:     .res 2
.segment "CODE"
