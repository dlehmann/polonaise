; sound.s - the SID: the disco loop (gen/music.inc, one event per 16th note) and
; the sound effects. sound_tick runs in the frame interrupt once per logic tick
; (60 per second), so the music follows the beat of the dance floor lights:
; 16th notes of 7 and 8 ticks, 30 ticks per beat (120 bpm).
;
; Voice 1: bass and drums (a drum hit at the start of a bass note, then the note; hi-hats
; between the notes), voice 2: chord stabs and melody, voice 3: the sound effects alone -
; so an effect never interrupts the music.

.segment "RODATA"
.include "music.inc"

; drum hits on voice 1: per type the ticks of waveform / frequency high byte; after them the
; bass note sounds (with the gate still on), the low pass filter only on the bass
drum_lo:    .byte 0, <dw_kick, <dw_clap, <dw_chat, <dw_ohat
drum_hi:    .byte 0, >dw_kick, >dw_clap, >dw_chat, >dw_ohat
drum_len:   .byte 0, 3, 3, 1, 1
dw_kick:    .byte $11, $28, $11, $14, $11, $0a
dw_clap:    .byte $11, $28, $81, $26, $81, $22
dw_chat:    .byte $81, $f0
dw_ohat:    .byte $81, $e8
BASS_TICKS = 6              ; a bass note (with its drum hit) lasts 6 ticks
; vibrato of the melody: frequency offsets (scaled by the note)
vib_tab:    .byte 0, 1, 2, 1, 0, $ff, $fe, $ff

.segment "ZEROPAGE"
sfx_pos:    .res 2
v1_ptr:     .res 2

.segment "BSS"
freq_lo:    .res 108
freq_hi:    .res 108
mus_on:     .res 1
mus_pause:  .res 1
mus_step:   .res 1
mus_tick:   .res 1
v1_t:       .res 1          ; ticks into the step on voice 1
v1_note:    .res 1          ; the bass note of the step (0: none)
v1_drum:    .res 1          ; the drum of the step
mel_kind:   .res 1          ; 0 silent, 1 stab, 2 melody
mel_t:      .res 1
mel_len:    .res 1
mel_chord:  .res 1
mel_note:   .res 1
sfx_on:     .res 1
sfx_wait:   .res 1
sfx_wave:   .res 1
sfx_f:      .res 2
sfx_d:      .res 2
sfx_slide:  .res 1
sfx_req:    .res 1          ; an effect to start ($ff: none)
sfx_r:      .res 7          ; the registers of voice 3 (frequency, pulse, control, ADSR)
snd_t:      .res 1

.segment "CODE"

; Sets up the SID and the note table of the system (PAL or NTSC).
sound_init:
        ldx #107
@f:     lda pal
        beq @n
        lda freq_lo_pal, x
        sta freq_lo, x
        lda freq_hi_pal, x
        sta freq_hi, x
        jmp @nx
@n:     lda freq_lo_ntsc, x
        sta freq_lo, x
        lda freq_hi_ntsc, x
        sta freq_hi, x
@nx:    dex
        bpl @f
        lda #0
        sta mus_on
        sta mus_pause
        sta sfx_on
        sta mel_kind
        sta v1_note
        sta v1_drum
        lda #$ff
        sta sfx_req
        ; filter: low pass on voice 1 (switched off for the drum hits)
        lda #0
        sta SID + $15
        lda #$38
        sta SID + $16
        lda #$a1
        sta SID + $17
        lda #$1f
        sta SID + $18
        jsr voice1_adsr
        lda #1
        sta sound_on
        rts

voice1_adsr:
        lda #$06
        sta SID + 5
        lda #$a2
        sta SID + 6
        rts

; Starts the music from the beginning (unless it plays).
music_start:
        lda mus_on
        bne @r
        sei
        lda #0
        sta mus_step
        sta mus_tick
        sta mus_pause
        sta v1_note
        sta v1_drum
        jsr voice1_adsr
        lda #1
        sta mus_on
        cli
@r:     rts

; Stops the music; the notes fade with a long release (game over).
music_fade:
        sei
        lda #0
        sta mus_on
        sta mel_kind
        lda #$0a
        sta SID + 6
        sta SID + 13
        lda #$20
        sta SID + 4
        lda #$40
        sta SID + 11
        cli
        rts

; The pause: the music stands still (the effects play on).
sound_pause:
        lda #1
        sta mus_pause
        lda #$20
        sta SID + 4
        lda #$40
        sta SID + 11
        rts

sound_resume:
        lda #0
        sta mus_pause
        rts

; Plays the effect A (it replaces one that plays).
sfx_play:
        sta sfx_req
        rts

; The sound of the game event X.
sound_event:
        lda ev_type, x
        cmp #EV_CATCH
        bne @n1
        lda ev_index, x
        cmp #GUEST_STAR
        bne @c
        lda #SFX_CATCH_STAR
        jmp sfx_play
@c:     lda ev_count, x
        cmp #6
        bcc @c1
        lda #5
@c1:    clc
        adc #SFX_CATCH1 - 1
        jmp sfx_play
@n1:    cmp #EV_GAME_OVER
        bne @n2
        jsr music_fade
        lda #SFX_GAME_OVER
        jmp sfx_play
@n2:    tay
        lda event_sfx, y
        bmi @r
        jmp sfx_play
@r:     rts

.segment "RODATA"
; the effect of each event ($ff: silent)
event_sfx:
        .byte SFX_TURN, SFX_GO, SFX_DENY, $ff, $ff, SFX_FLEE, SFX_STAR, SFX_STAR_GONE, SFX_CRASH
        .byte SFX_EXTRA_LIFE, SFX_SONG_START, $ff, SFX_CLEARED, $ff
.segment "CODE"

; ---------------------------------------------------------------- the tick (in the interrupt)

sound_tick:
        lda sfx_req
        bmi @ns
        jsr sfx_start
@ns:    lda mus_on
        beq @nm
        lda mus_pause
        bne @nm
        jsr music_tick
@nm:    lda sfx_on
        beq @r
        jmp sfx_tick
@r:     rts

; Starts the effect sfx_req on voice 3.
sfx_start:
        ldx sfx_req
        lda sfx_lo, x
        sta sfx_pos
        lda sfx_hi, x
        sta sfx_pos + 1
        ldx #6
        lda #0
@c:     sta sfx_r, x
        dex
        bpl @c
        sta SID + 18            ; a playing effect stops: gate off
        sta sfx_wait
        sta sfx_slide
        lda #1
        sta sfx_on
        lda #$ff
        sta sfx_req
        rts

music_tick:
        ; a new 16th note?
        lda mus_tick
        bne @run
        ldx mus_step
        lda mus_bass, x
        sta v1_note
        lda mus_drum, x
        sta v1_drum
        lda #0
        sta v1_t
        ; voice 2: melody or stab
        lda mus_v3, x
        beq @run
        bmi @stab
        sta mel_note
        lda mus_v3len, x
        ; ticks = steps * 7.5
        sta snd_t
        asl
        asl
        asl
        sec
        sbc snd_t
        sta mel_len
        lda #2
        sta mel_kind
        lda #0
        sta mel_t
        jsr mel_setup_melody
        jmp @run
@stab:  and #$7f
        sta mel_chord
        lda #9
        sta mel_len
        lda #1
        sta mel_kind
        lda #0
        sta mel_t
        jsr mel_setup_stab
@run:   jsr voice1_tick
        jsr mel_tick
        ; the next 16th: 7 or 8 ticks
        inc mus_tick
        lda mus_step
        and #1
        clc
        adc #7
        cmp mus_tick
        bne @r
        lda #0
        sta mus_tick
        inc mus_step
@r:     rts

; Voice 1 in the tick v1_t of the step: the drum hit (filter off), then the bass note
; (filter on), its end; a step without a bass note may have a hi-hat.
voice1_tick:
        ldx v1_t
        inc v1_t
        ldy v1_drum
        lda v1_note
        bne @bass
        ; no note: the hi-hat of the step
        cpy #0
        beq @r
        cpx #0
        bne @off1
        jsr drum_ptr_y
        jmp @hit
@off1:  cpx #1
        bne @r
        lda #$80
        sta SID + 4
@r:     rts
@bass:  cpx #BASS_TICKS
        beq @end
        bcs @r
        txa
        cmp drum_len, y
        bcs @note
        ; the drum hit: tick x of the drum
        cpx #0
        bne @h2
        jsr drum_ptr_y
@h2:    txa
        asl
        tay
        lda (v1_ptr), y
        pha
        iny
        lda (v1_ptr), y
        sta SID + 1
        lda #0
        sta SID + 0
        lda #$a0                ; no filter on the drums
        sta SID + $17
        pla
        sta SID + 4
        rts
@note:  ; the bass note (on the first tick, or after the drum hit)
        cmp drum_len, y
        bne @r
        ldy v1_note
        lda freq_lo, y
        sta SID + 0
        lda freq_hi, y
        sta SID + 1
        lda #$a1
        sta SID + $17
        lda #$21
        sta SID + 4
        rts
@end:   lda #$20
        sta SID + 4
        rts
@hit:   ; tick 0 of a hi-hat
        ldy #0
        lda (v1_ptr), y
        pha
        iny
        lda (v1_ptr), y
        sta SID + 1
        lda #0
        sta SID + 0
        lda #$a0
        sta SID + $17
        pla
        sta SID + 4
        rts

; v1_ptr = the waveform table of the drum Y.
drum_ptr_y:
        lda drum_lo, y
        sta v1_ptr
        lda drum_hi, y
        sta v1_ptr + 1
        rts

mel_setup_stab:
        lda #$00
        sta SID + 9
        lda #$06
        sta SID + 10
        lda #$04
        sta SID + 12
        lda #$40
        sta SID + 13
        lda #$40
        sta SID + 11
        rts

mel_setup_melody:
        lda #$00
        sta SID + 9
        lda #$04
        sta SID + 10
        lda #$06
        sta SID + 12
        lda #$a6
        sta SID + 13
        ldy mel_note
        lda freq_lo, y
        sta SID + 7
        lda freq_hi, y
        sta SID + 8
        lda #$40
        sta SID + 11
        lda #$41
        sta SID + 11
        rts

mel_tick:
        lda mel_kind
        bne @go
        rts
@go:    cmp #1
        bne @mel
        ; stab: the chord as a fast arpeggio
        lda mel_t
        ldx #3
@m3:    cmp #3
        bcc @a
        sbc #3
        bcs @m3
@a:     tax
        ldy mel_chord
        lda mus_chord1, y
        cpx #1
        bne @a1
        lda mus_chord2, y
@a1:    cpx #2
        bne @a2
        lda mus_chord3, y
@a2:    tay
        lda freq_lo, y
        sta SID + 7
        lda freq_hi, y
        sta SID + 8
        lda #$41
        sta SID + 11
        jmp @len
@mel:   ; melody: vibrato after 8 ticks
        lda mel_t
        cmp #8
        bcc @len
        and #7
        tax
        ldy mel_note
        lda vib_tab, x
        bmi @neg
        asl
        asl
        clc
        adc freq_lo, y
        sta SID + 7
        lda freq_hi, y
        adc #0
        sta SID + 8
        jmp @len
@neg:   asl
        asl
        clc
        adc freq_lo, y
        sta SID + 7
        lda freq_hi, y
        adc #$ff
        sta SID + 8
@len:   inc mel_t
        lda mel_t
        cmp mel_len
        bcc @r
        lda #0
        sta mel_kind
        lda #$40
        sta SID + 11
@r:     rts

; ---------------------------------------------------------------- effects

sfx_tick:
        jsr sfx_run
        ; fall through

; Copies the registers of the effect into its voice (the control register last).
sfx_out:
        ldx #14
        lda sfx_r + 5
        sta SID + 5, x
        lda sfx_r + 6
        sta SID + 6, x
        lda sfx_r
        sta SID, x
        lda sfx_r + 1
        sta SID + 1, x
        lda sfx_r + 2
        sta SID + 2, x
        lda sfx_r + 3
        sta SID + 3, x
        lda sfx_r + 4
        sta SID + 4, x
        rts

sfx_run:
        lda sfx_slide
        beq @ns
        ; a slide: the frequency moves every tick
        clc
        lda sfx_f
        adc sfx_d
        sta sfx_f
        sta sfx_r + 0
        lda sfx_f + 1
        adc sfx_d + 1
        sta sfx_f + 1
        sta sfx_r + 1
@ns:    lda sfx_wait
        beq @cmd
        dec sfx_wait
        beq @cmd
        rts
@cmd:   lda #0
        sta sfx_slide
        ldy #0
        lda (sfx_pos), y
        bne @c1
        ; the end: the voice goes back to the music
        sta sfx_on
        sta sfx_r + 4
        jmp sfx_out
@c1:    cmp #SC_ADSR
        bne @c2
        iny
        lda (sfx_pos), y
        sta sfx_r + 5
        iny
        lda (sfx_pos), y
        sta sfx_r + 6
        lda #3
        jsr sfx_adv
        jmp @cmd
@c2:    cmp #SC_PW
        bne @c3
        iny
        lda (sfx_pos), y
        sta sfx_r + 2
        iny
        lda (sfx_pos), y
        sta sfx_r + 3
        lda #3
        jsr sfx_adv
        jmp @cmd
@c3:    cmp #SC_NOTE
        bne @c4
        iny
        lda (sfx_pos), y
        sta sfx_wave
        iny
        lda (sfx_pos), y
        tax
        lda freq_lo, x
        sta sfx_r + 0
        lda freq_hi, x
        sta sfx_r + 1
        iny
        lda (sfx_pos), y
        sta sfx_wait
        jsr sfx_gate
        lda #4
        jmp sfx_adv
@c4:    cmp #SC_FREQ
        bne @c5
        iny
        lda (sfx_pos), y
        sta sfx_wave
        iny
        lda (sfx_pos), y
        sta sfx_r + 1
        iny
        lda (sfx_pos), y
        sta sfx_r + 0
        iny
        lda (sfx_pos), y
        sta sfx_wait
        jsr sfx_gate
        lda #5
        jmp sfx_adv
@c5:    cmp #SC_SLIDE
        bne @c6
        iny
        lda (sfx_pos), y
        sta sfx_wave
        iny
        lda (sfx_pos), y
        sta sfx_f + 1
        sta sfx_r + 1
        iny
        lda (sfx_pos), y
        sta sfx_f
        sta sfx_r + 0
        iny
        lda (sfx_pos), y
        sta sfx_d + 1
        iny
        lda (sfx_pos), y
        sta sfx_d
        iny
        lda (sfx_pos), y
        sta sfx_wait
        lda #1
        sta sfx_slide
        jsr sfx_gate
        lda #7
        jmp sfx_adv
@c6:    ; OFF
        lda sfx_wave
        and #$fe
        sta sfx_r + 4
        iny
        lda (sfx_pos), y
        sta sfx_wait
        lda #2
        jmp sfx_adv

; The waveform with the gate on (a new note restarts the envelope only after a gate off).
sfx_gate:
        lda sfx_wave
        sta sfx_r + 4
        rts

sfx_adv:
        clc
        adc sfx_pos
        sta sfx_pos
        bcc @r
        inc sfx_pos + 1
@r:     rts
