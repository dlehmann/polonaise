; sys.s - the machine: memory setup, the raster interrupts that switch the character
; rows between text and bitmap, the frame interrupt (ticks, input, sprites, sound),
; joystick and keyboard.

.segment "ZEROPAGE"
irq_a:      .res 1
irq_x:      .res 1
irq_y:      .res 1

.segment "BSS"
pal:        .res 1          ; 1: PAL (50 Hz, 6 ticks per 5 frames), 0: NTSC
frame:      .res 1          ; frames since the start
frame5:     .res 1          ; frame counter modulo 5
frame_flag: .res 1          ; set by the frame interrupt
ticks_due:  .res 1          ; logic ticks to run (60 per second)
irq_ticks:  .res 1          ; ticks of the current frame (for the sound)
sound_on:   .res 1          ; the sound player runs in the frame interrupt

; rows: the mode of each character row, applied with the next frame
rowmode:    .res 25
rows_dirty: .res 1
shake_x:    .res 1          ; horizontal scroll of the bitmap rows (screen shake)
bgcolor:    .res 1          ; $d021 (the crash flash)
text_d022:  .res 1
text_d023:  .res 1
logo_d022:  .res 1
logo_d023:  .res 1

; the compiled list of raster interrupts: line, $d011, $d016, $d018, $d022, $d023
IRQ_MAX = 26
irq_line:   .res IRQ_MAX
irq_d011:   .res IRQ_MAX
irq_d016:   .res IRQ_MAX
irq_d018:   .res IRQ_MAX
irq_d022:   .res IRQ_MAX
irq_d023:   .res IRQ_MAX
irq_n:      .res 1
irq_i:      .res 1
top_d011:   .res 1
top_d016:   .res 1
top_d018:   .res 1
top_d022:   .res 1
top_d023:   .res 1

; sprite shadow registers, copied into the VIC by the frame interrupt
spr_x:      .res 8
spr_xhi:    .res 8
spr_y:      .res 8
spr_col:    .res 8
spr_ptr:    .res 8
spr_en:     .res 1
spr_mc:     .res 1
spr_xe:     .res 1
spr_ye:     .res 1
spr_pri:    .res 1
spr_mc1:    .res 1
spr_mc2:    .res 1

; input: the joystick state and the presses since they were last read
joy_now:    .res 1          ; bits: 0 up, 1 down, 2 left, 3 right, 4 fire (1 = pressed)
joy_last:   .res 1
INQ_SIZE = 8
inq:        .res INQ_SIZE   ; presses: DIR_*, IN_FIRE, IN_KEY + key (a ring)
inq_key:    .res INQ_SIZE
inq_head:   .res 1          ; written only by the interrupt
inq_tail:   .res 1          ; written only by the main program
key_last:   .res 1
fire_held:  .res 1          ; frames the fire button has been held

IN_FIRE = 8
IN_KEY  = 9

.segment "CODE"

; ---------------------------------------------------------------- setup

; Called once at the start (interrupts off): ROMs off, VIC bank 3, sprites and
; character set copied, the interrupts started.
sys_init:
        sei
        cld
        lda #$7f
        sta CIA1 + $0d          ; no CIA interrupts
        sta CIA2 + $0d
        lda CIA1 + $0d
        lda CIA2 + $0d
        lda #$35                ; RAM, I/O, no ROMs
        sta $01
        lda #<nmi
        sta $fffa
        lda #>nmi
        sta $fffb
        lda #<irq
        sta $fffe
        lda #>irq
        sta $ffff
        lda #0
        sta $d01a
        sta $d015
        lda #$0b                ; screen off while setting up
        sta $d011
        lda #BLACK
        sta $d020
        sta $d021
        sta bgcolor
        jsr detect_pal

        ; VIC bank 3: $dd00 bits 0..1 = 0
        lda CIA2 + 2
        ora #3
        sta CIA2 + 2
        lda CIA2
        and #$fc
        sta CIA2

        ; CIA1 port A output (keyboard columns), port B input
        lda #$ff
        sta CIA1 + 2
        lda #0
        sta CIA1 + 3

        ; clear the bitmap, the screen and the colours
        lda #<BITMAP
        sta ptr
        lda #>BITMAP
        sta ptr + 1
        ldx #$1f
        lda #0
        tay
@clr:   sta (ptr), y
        iny
        bne @clr
        inc ptr + 1
        dex
        bne @clr
        ldx #0
@clr2:  lda #0
        sta SCREEN, x
        sta SCREEN + $100, x
        sta SCREEN + $200, x
        sta SCREEN + $2e8, x
        sta COLRAM, x
        sta COLRAM + $100, x
        sta COLRAM + $200, x
        sta COLRAM + $2e8, x
        inx
        bne @clr2

        ; the character set and the static sprites
        lda #<charset_data
        sta ptr
        lda #>charset_data
        sta ptr + 1
        lda #<CHARSET
        sta ptr2
        lda #>CHARSET
        sta ptr2 + 1
        ldx #8
        jsr copy_pages
        lda #$34                ; all RAM: the sprites go under the I/O area
        sta $01
        lda #<sprite_data
        sta ptr
        lda #>sprite_data
        sta ptr + 1
        lda #<SPRSTAT
        sta ptr2
        lda #>SPRSTAT
        sta ptr2 + 1
        ldx #>(sprite_data_end - sprite_data + 255)
        jsr copy_pages
        lda #$35
        sta $01

        ; SID: silence
        ldx #$18
        lda #0
@sid:   sta SID, x
        dex
        bpl @sid

        lda #0
        sta frame
        sta frame5
        sta ticks_due
        sta inq_head
        sta inq_tail
        sta sound_on
        sta spr_en
        sta shake_x
        sta text_d022
        sta text_d023
        lda #LRED
        sta logo_d022
        lda #PURPLE
        sta logo_d023
        lda #$ff
        sta joy_last
        sta key_last
        ; all rows text until something else is set
        ldx #24
        lda #RM_BLANK
@rm:    sta rowmode, x
        dex
        bpl @rm
        lda #RM_TEXT
        sta rowmode
        jsr compile_rows

        ; the frame interrupt
        lda #$1b
        sta $d011
        lda #251
        sta $d012
        lda #1
        sta $d01a
        sta $d019
        cli
        rts

; Copies X pages from (ptr) to (ptr2).
copy_pages:
        ldy #0
@l:     lda (ptr), y
        sta (ptr2), y
        iny
        bne @l
        inc ptr + 1
        inc ptr2 + 1
        dex
        bne @l
        rts

; PAL: the raster counter goes beyond line 300.
detect_pal:
@w1:    lda $d011
        bpl @w1
        lda #0
        sta pal
@w2:    lda $d012
        cmp #$20
        bcc @n
        lda #1
        sta pal
@n:     lda $d011
        bmi @w2
        rts

nmi:    rti

; ---------------------------------------------------------------- rows

; Turns rowmode into the list of raster interrupts (called by the frame interrupt).
compile_rows:
        ldx rowmode
        jsr row_values
        lda val_d011
        sta top_d011
        lda val_d016
        sta top_d016
        lda val_d018
        sta top_d018
        lda val_d022
        sta top_d022
        lda val_d023
        sta top_d023
        ldy #0                  ; entries
        ldx #1                  ; row
@row:   lda rowmode, x
        cmp rowmode - 1, x
        beq @next
        stx cr_row
        tax
        jsr row_values
        ldx cr_row
        txa
        asl
        asl
        asl
        clc
        adc #50
        sta irq_line, y
        lda val_d011
        sta irq_d011, y
        lda val_d016
        sta irq_d016, y
        lda val_d018
        sta irq_d018, y
        lda val_d022
        sta irq_d022, y
        lda val_d023
        sta irq_d023, y
        iny
@next:  inx
        cpx #25
        bne @row
        sty irq_n
        rts

; The register values of the row mode X.
row_values:
        lda #$08
        sta val_d016
        lda text_d022
        sta val_d022
        lda text_d023
        sta val_d023
        lda #$1b
        sta val_d011
        lda #D018_TEXT
        sta val_d018
        cpx #RM_TEXT
        beq @done
        cpx #RM_LOGO
        bne @nlogo
        lda #$18
        sta val_d016
        lda logo_d022
        sta val_d022
        lda logo_d023
        sta val_d023
        rts
@nlogo: cpx #RM_BITMAP
        bne @blank
        lda #$3b
        sta val_d011
        lda #D018_BITMAP
        sta val_d018
        lda shake_x
        ora #$18
        sta val_d016
        rts
@blank: lda #$7b
        sta val_d011
@done:  rts

.segment "BSS"
val_d011:   .res 1
val_d016:   .res 1
val_d018:   .res 1
val_d022:   .res 1
val_d023:   .res 1
cr_row:     .res 1
.segment "CODE"

; Sets the rows A..X (inclusive) to the mode Y.
set_rows:
        sta sr_first
        tya
@l:     sta rowmode, x
        dex
        bmi @done
        cpx sr_first
        bcs @l
@done:  lda #1
        sta rows_dirty
        rts

.segment "BSS"
sr_first:   .res 1
.segment "CODE"

; Waits for the next frame interrupt.
wait_frame:
        lda #0
        sta frame_flag
@w:     lda frame_flag
        beq @w
        rts

; ---------------------------------------------------------------- interrupts

irq:    sta irq_a
        stx irq_x
        sty irq_y
        lda $d019
        sta $d019
        ldx irq_i
        cpx irq_n
        bcs frame_irq
        ; a row switch: wait for the line before the last line of the row above
        lda irq_line, x
        sec
        sbc #1
@w:     cmp $d012               ; (no waiting if the interrupt came late)
        beq @go
        bcs @w
@go:    ; both writes of $d011 fall into the right border, where the jitter of the wait
        ; does not show: in the line before, the last line of the row goes black (an
        ; invalid mode), so the pointers can change unseen; at its end the new mode
        ; comes, before the bad line of the row
        ldy #10
@d1:    dey
        bne @d1
        lda #$7b
        sta $d011
        lda irq_d018, x
        sta $d018
        lda irq_d016, x
        sta $d016
        lda irq_d022, x
        sta $d022
        lda irq_d023, x
        sta $d023
        lda irq_d011, x
        ldy #5
@d2:    dey
        bne @d2
        sta $d011
        inx
        stx irq_i
        jsr next_irq
        lda irq_a
        ldx irq_x
        ldy irq_y
        rti

; Sets the raster line of the next interrupt (X = index of the next entry).
next_irq:
        cpx irq_n
        bcs @frame
        lda irq_line, x
        sec
        sbc #2
        sta $d012
        rts
@frame: lda #251
        sta $d012
        rts

; At line 251: the rows of the next frame start with the setting of row 0.
frame_irq:
        lda top_d011
        sta $d011
        lda top_d016
        sta $d016
        lda top_d018
        sta $d018
        lda top_d022
        sta $d022
        lda top_d023
        sta $d023
        lda bgcolor
        sta $d021
        cld

        ; sprites
        ldx #7
        ldy #14
        lda #0
        sta fi_msb
@spr:   lda spr_x, x
        sta $d000, y
        lda spr_y, x
        sta $d001, y
        lda spr_col, x
        sta $d027, x
        lda spr_ptr, x
        sta SPRPTR, x
        lda spr_xhi, x
        lsr
        rol fi_msb
        dey
        dey
        dex
        bpl @spr
        lda fi_msb
        sta $d010
        lda spr_en
        sta $d015
        lda spr_mc
        sta $d01c
        lda spr_xe
        sta $d01d
        lda spr_ye
        sta $d017
        lda spr_pri
        sta $d01b
        lda spr_mc1
        sta $d025
        lda spr_mc2
        sta $d026

        ; ticks: PAL 6 per 5 frames, NTSC one per frame
        inc frame
        lda #1
        ldx pal
        beq @nt
        ldx frame5
        bne @n5
        lda #2
@n5:    inx
        cpx #5
        bne @f5
        ldx #0
@f5:    stx frame5
@nt:    sta irq_ticks
        clc
        adc ticks_due
        cmp #8                  ; the main loop is behind: do not pile up
        bcc @td
        lda #8
@td:    sta ticks_due

        jsr read_input
        lda sound_on
        beq @nos
@snd:   jsr sound_tick
        dec irq_ticks
        bne @snd
@nos:
        lda rows_dirty
        beq @nr
        lda #0
        sta rows_dirty
        jsr compile_rows
@nr:    lda #0
        sta irq_i
        tax
        jsr next_irq
        lda #1
        sta frame_flag
        lda irq_a
        ldx irq_x
        ldy irq_y
        rti

.segment "BSS"
fi_msb:     .res 1
.segment "CODE"

; ---------------------------------------------------------------- input

; Reads the joysticks (port 2 and port 1) and the keyboard; new presses go into the queue.
read_input:
        lda #$ff
        sta CIA1
        lda CIA1 + 1            ; joystick 1 (no keyboard column selected)
        sta ri_j1
        lda CIA1                ; joystick 2
        and ri_j1
        eor #$ff
        and #$1f
.ifdef TEST
        ora ap_joy
.endif
        sta joy_now
        ; fire held (for the long press in the pause)
        and #$10
        beq @nf
        lda fire_held
        cmp #255
        beq @f
        inc fire_held
        bne @f
@nf:    sta fire_held
@f:     lda joy_last
        eor #$ff
        and joy_now             ; newly pressed
        sta ri_new
        lda joy_now
        sta joy_last
        lda ri_new
        lsr
        bcc @nu
        pha
        lda #DIR_UP
        jsr push_input
        pla
@nu:    lsr
        bcc @nd
        pha
        lda #DIR_DOWN
        jsr push_input
        pla
@nd:    lsr
        bcc @nl
        pha
        lda #DIR_LEFT
        jsr push_input
        pla
@nl:    lsr
        bcc @nr
        pha
        lda #DIR_RIGHT
        jsr push_input
        pla
@nr:    lsr
        bcc @nfi
        lda #IN_FIRE
        jsr push_input
@nfi:
        ; the keyboard, unless joystick 1 is pulling lines
        lda ri_j1
        cmp #$ff
        bne @nokey
        jsr scan_key
        cmp key_last
        beq @nokey
        sta key_last
        cmp #0
        beq @nokey
        sta ri_new
        lda #IN_KEY
        jsr push_input
@nokey: lda #$ff
        sta CIA1
        rts

; Appends the input A (with the key ri_new) to the queue (in the interrupt). The queue
; is a ring that needs no locking: the interrupt moves only the head, the main program
; only the tail, so the raster interrupts are never held up.
push_input:
        ldx inq_head
        sta inq, x
        lda ri_new
        sta inq_key, x
        inx
        txa
        and #INQ_SIZE - 1
        cmp inq_tail
        beq @full               ; full: the press is dropped
        sta inq_head
@full:  rts

; Takes the oldest input: A = input (carry clear) or carry set if none; the key in X.
pop_input:
        ldy inq_tail
        cpy inq_head
        beq @none
        ldx inq_key, y
        lda inq, y
        pha
        iny
        tya
        and #INQ_SIZE - 1
        sta inq_tail
        pla
        clc
        rts
@none:  sec
        rts

clear_input:
        lda inq_head
        sta inq_tail
        rts

; The first key pressed (as a code of key_codes), 0 if none.
scan_key:
        ldx #0                  ; column
        lda #$fe
@col:   sta CIA1
        ldy CIA1 + 1
        cpy #$ff
        bne @found
        sec
        rol
        inx
        cpx #8
        bne @col
        lda #0
        rts
@found: tya
        ldy #0
@bit:   lsr
        bcc @key
        iny
        bne @bit
@key:   txa
        asl
        asl
        asl
        sty sk_row
        ora sk_row
        tax
        ; ignore the shift keys
        lda key_codes, x
        rts

.segment "BSS"
ri_j1:      .res 1
ri_new:     .res 1
sk_row:     .res 1
.segment "CODE"

KEY_RETURN = 13
KEY_DEL    = 20
KEY_STOP   = 3
KEY_LEFT   = 157
KEY_RIGHT  = 29
KEY_UP     = 145
KEY_DOWN   = 17
KEY_F1     = 133

.segment "RODATA"
; the keyboard matrix: column (bit of $dc00) * 8 + row (bit of $dc01)
key_codes:
        .byte KEY_DEL, KEY_RETURN, KEY_RIGHT, 0, KEY_F1, 0, 0, KEY_DOWN
        .byte "3", "W", "A", "4", "Z", "S", "E", 0
        .byte "5", "R", "D", "6", "C", "F", "T", "X"
        .byte "7", "Y", "G", "8", "B", "H", "U", "V"
        .byte "9", "I", "J", "0", "M", "K", "O", "N"
        .byte "+", "P", "L", "-", ".", ":", "@", ","
        .byte 0, "*", ";", 0, 0, "=", 0, "/"
        .byte "1", 0, 0, "2", " ", 0, "Q", KEY_STOP
.segment "CODE"
