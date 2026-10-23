; autopilot.s - (test builds only, make TEST=1) a player that presses the buttons by
; itself: it starts games, walks to the nearest guest and confirms the screens, so
; the emulator can run the game unattended.

.segment "BSS"
ap_frames:  .res 1
ap_best:    .res 1
ap_bestd:   .res 1
ap_d:       .res 1
ap_c:       .res 1
ap_min:     .res 1
ap_last:    .res 1
ap_joy:     .res 1
ap_t:       .res 2
.segment "CODE"

autopilot:
.ifdef TEST_SCRIPT
        jsr ap_script
.endif
        inc ap_frames
        lda mode
        cmp #M_GAME
        beq @game
.if .defined(TEST_SCRIPT)
.if TEST_SCRIPT = 2
        cmp #M_ENTRY
        bne @ne
        jmp ap_entry
@ne:
.endif
.endif
        lda ap_frames
        cmp #120
        bcc @r
        lda #0
        sta ap_frames
        lda #IN_FIRE
        jmp ap_push
@r:     rts
@game:  lda paused
        bne @r
        lda phase
        cmp #PHASE_INTRO
        beq @confirm
        cmp #PHASE_CLEARED
        beq @confirm
        cmp #PHASE_PLAY
        bne @r
        lda moving
        bne @move
        lda ap_frames
        cmp #40
        bcc @r
        lda #0
        sta ap_frames
        jsr ap_dir
        jmp ap_push
@move:  lda step_timer
        cmp ap_last
        sta ap_last
        beq @r
        cmp #1
        bne @r
        lda queue_n
        bne @r
        jsr ap_dir
        cmp dir
        beq @r
        jmp ap_push
@confirm:
        lda phase
        cmp #PHASE_CLEARED
        bne @ci
        lda timer + 1
        beq @r                  ; the summary is shown for 256 ticks
        bne @c
@ci:    lda timer + 1
        bne @c
        lda timer
        cmp #90
        bcc @r
@c:     lda ap_frames
        cmp #30
        bcc @r
        lda #0
        sta ap_frames
        lda #IN_FIRE
        jmp ap_push

ap_push:
        sei
        jsr push_input
        cli
        rts

; The free direction that leads closest to a guest.
ap_dir:
        lda dir
        sta ap_best
        lda #$ff
        sta ap_bestd
        lda #0
        sta ap_d
@d:     lda body
        ldx ap_d
        jsr next_cell
        sta ap_c
        jsr step_blocked
        bcs @next
        lda length
        cmp #2
        bcc @ok
        lda ap_c
        cmp body + 1
        beq @next
@ok:    ; the distance to the nearest guest
        lda #$ff
        sta ap_min
        ldy #MAX_GUESTS - 1
@g:     lda g_active, y
        beq @ng
        tya
        pha
        lda g_cell, y
        tay
        ldx ap_c
        jsr distance
        cmp ap_min
        bcs @nm
        sta ap_min
@nm:    pla
        tay
@ng:    dey
        bpl @g
        lda #0
        sta ap_frames
        lda ap_min
        cmp ap_bestd
        bcs @next
        sta ap_bestd
        lda ap_d
        sta ap_best
@next:  inc ap_d
        lda ap_d
        cmp #4
        bne @d
        lda ap_best
        rts

.ifdef TEST_SCRIPT
; A script of joystick states held from frame t0 to t1 of the game (TEST_SCRIPT 1: the pause).
ap_script:
        lda #0
        sta ap_joy
        lda mode
        cmp #M_GAME
        bne @r
        lda phase
        cmp #PHASE_PLAY
        bne @r
        inc ap_t
        bne @c
        inc ap_t + 1
@c:     ldx #0
@l:     lda script_t0_hi, x
        cmp #$ff
        beq @r
        ; t0 <= t < t1
        lda ap_t + 1
        cmp script_t0_hi, x
        bcc @n
        bne @a
        lda ap_t
        cmp script_t0_lo, x
        bcc @n
@a:     lda ap_t + 1
        cmp script_t1_hi, x
        bcc @in
        bne @n
        lda ap_t
        cmp script_t1_lo, x
        bcs @n
@in:    lda script_bits, x
        sta ap_joy
@n:     inx
        bne @l
@r:
        rts

.segment "RODATA"
script_t0_lo: .byte <100, <220, <400, <450, 0
script_t0_hi: .byte >100, >220, >400, >450, $ff
script_t1_lo: .byte <105, <225, <405, <530
script_t1_hi: .byte >105, >225, >405, >530
script_bits:  .byte $10, $10, $10, $10
.segment "CODE"
.endif

.if .defined(TEST_SCRIPT)
.if TEST_SCRIPT = 2
; The name entry: up, up, right, down, down, hold up, then fire.
ap_entry:
        inc ap_e
        lda ap_e
        ldx #0
@l:     ldy entry_script, x
        beq @hold
        cmp entry_script, x
        beq @push
        inx
        inx
        bne @l
@push:  lda entry_script + 1, x
        jmp ap_push
@hold:  lda ap_e
        cmp #100
        bcc @r
        cmp #150
        bcs @r
        lda #1
        sta ap_joy
@r:     rts
.segment "BSS"
ap_e:   .res 1
.segment "RODATA"
entry_script: .byte 20, DIR_UP, 30, DIR_UP, 40, DIR_RIGHT, 50, DIR_DOWN, 60, DIR_DOWN, 70, DIR_RIGHT, 200, IN_FIRE, 0
.segment "CODE"
.endif
.endif
