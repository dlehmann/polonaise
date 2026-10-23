; disk.s - the high score list on the disk (the file "POLONAISE.HI" on the drive the
; game was loaded from), with the routines of the KERNAL.

SETLFS = $ffba
SETNAM = $ffbd
OPEN   = $ffc0
CLOSE  = $ffc3
CHKIN  = $ffc6
CHRIN  = $ffcf
CLRCHN = $ffcc
LOAD   = $ffd5
SAVE   = $ffd8
READST = $ffb7

HS_MAGIC = $50              ; "P"

; the file, built and loaded in the cassette buffer ($033c..$03fb): below $8000, where no
; cartridge ROM can cover it while the KERNAL is in
hs_file     = $033c
hs_f_magic  = hs_file
hs_f_lang   = hs_file + 1
hs_f_count  = hs_file + 2
hs_f_name   = hs_file + 3
hs_f_score  = hs_f_name + MAX_SCORES * NAME_LEN
hs_f_song   = hs_f_score + MAX_SCORES * 3
hs_f_last   = hs_f_song + MAX_SCORES
hs_end      = hs_f_last + NAME_LEN
hs_load     = hs_file
.assert hs_end <= $03fc, error, "the high score file does not fit into the cassette buffer"

.segment "BSS"
disk_dev:   .res 1
disk_err:   .res 1

.segment "RODATA"
hs_name_str: .byte "POLONAISE.HI"
HS_NAME_LEN = * - hs_name_str
hs_scratch: .byte "S0:POLONAISE.HI"
HS_SCRATCH_LEN = * - hs_scratch

.segment "CODE"

; Empties the list (no file).
scores_clear:
        lda #0
        sta hs_count
        ldx #NAME_LEN - 1
@n:     sta last_name, x
        dex
        bpl @n
        rts

; Reads the list from the disk (at the start, while the KERNAL interrupt runs).
load_scores:
        jsr scores_clear
        lda #0
        sta hs_load
        lda #HS_NAME_LEN
        ldx #<hs_name_str
        ldy #>hs_name_str
        jsr SETNAM
        lda #1
        ldx disk_dev
        ldy #0                  ; load to the given address
        jsr SETLFS
        lda #0
        ldx #<hs_load
        ldy #>hs_load
        jsr LOAD
        bcs @err
        lda $90                 ; status: a read error?
        and #$bf
        bne @err
        lda hs_load
        cmp #HS_MAGIC
        bne @bad
        lda hs_load + 2
        cmp #MAX_SCORES + 1
        bcc @good
@bad:   jmp scores_clear
@good:  lda hs_f_lang
        and #1
        sta lang
        lda hs_f_count
        sta hs_count
        ldx #MAX_SCORES * NAME_LEN - 1
@nm:    lda hs_f_name, x
        sta hs_name, x
        dex
        bpl @nm
        ldx #MAX_SCORES * 3 - 1
@sc:    lda hs_f_score, x
        sta hs_score, x
        dex
        bpl @sc
        ldx #MAX_SCORES - 1
@sg:    lda hs_f_song, x
        sta hs_song, x
        dex
        bpl @sg
        ldx #NAME_LEN - 1
@ln:    lda hs_f_last, x
        sta last_name, x
        dex
        bpl @ln
        rts
@err:   ; no file (the first start): read the error channel, so the drive light stops blinking
        jsr read_status
        jmp scores_clear

; Reads the error channel of the drive: A = 0 if it says "00" (KERNAL in).
read_status:
        lda #0
        tax
        tay
        jsr SETNAM
        lda #15
        ldx disk_dev
        ldy #15
        jsr SETLFS
        jsr OPEN
        bcs @e
        ldx #15
        jsr CHKIN
        bcs @e
        jsr CHRIN
        sta sv_d1
        jsr CHRIN
        ora sv_d1
        sta sv_d1
        ; the rest of the message
@rest:  jsr READST
        bne @end
        jsr CHRIN
        cmp #13
        bne @rest
@end:   lda sv_d1
        cmp #'0'
        beq @c15
@e:     lda #1
        sta sv_d1
@c15:   jsr CLRCHN
        lda #15
        jsr CLOSE
        lda sv_d1
        cmp #'0'
        beq @ok
        lda #1
        rts
@ok:    lda #0
        rts

; Writes the list to the disk: a message, the interrupts off, KERNAL in.
save_scores:
        ; the screen: all text, only the message
        jsr fx_reset
        lda #0
        sta spr_en
        lda #0
        ldx #24
        ldy #RM_TEXT
        jsr set_rows
        jsr update_vis
        jsr wait_frame
        lda #0
        ldx #24
        jsr clear_rows
        lda #T_DISK_SAVING
        ldx #12
        ldy #YELLOW
        jsr say
        jsr wait_frame
        jsr wait_frame
        ; the file
        lda #HS_MAGIC
        sta hs_f_magic
        lda lang
        sta hs_f_lang
        lda hs_count
        sta hs_f_count
        ldx #MAX_SCORES * NAME_LEN - 1
@nm:    lda hs_name, x
        sta hs_f_name, x
        dex
        bpl @nm
        ldx #MAX_SCORES * 3 - 1
@sc:    lda hs_score, x
        sta hs_f_score, x
        dex
        bpl @sc
        ldx #MAX_SCORES - 1
@sg:    lda hs_song, x
        sta hs_f_song, x
        dex
        bpl @sg
        ldx #NAME_LEN - 1
@ln:    lda last_name, x
        sta hs_f_last, x
        dex
        bpl @ln
        jsr kernal_on
        ; scratch the old file, then save
        lda #HS_SCRATCH_LEN
        ldx #<hs_scratch
        ldy #>hs_scratch
        jsr SETNAM
        lda #15
        ldx disk_dev
        ldy #15
        jsr SETLFS
        jsr OPEN
        lda #15
        jsr CLOSE
        jsr CLRCHN
        lda #HS_NAME_LEN
        ldx #<hs_name_str
        ldy #>hs_name_str
        jsr SETNAM
        lda #1
        ldx disk_dev
        ldy #0
        jsr SETLFS
        lda #<hs_file
        sta $fb
        lda #>hs_file
        sta $fc
        lda #$fb
        ldx #<hs_end
        ldy #>hs_end
        jsr SAVE
        lda #0
        rol
        sta disk_err
        ; the error channel: "00" is fine
        jsr read_status
        ora disk_err
        sta disk_err
        jsr kernal_off
        lda disk_err
        beq @r
        lda #0
        ldx #24
        jsr clear_rows
        lda #T_DISK_ERROR
        ldx #12
        ldy #LRED
        jsr say
        ldx #100
@w:     txa
        pha
        jsr wait_frame
        pla
        tax
        dex
        bne @w
@r:     rts

.segment "BSS"
sv_d1:      .res 1
.segment "CODE"

; The KERNAL in, no raster interrupts, the sound silent.
kernal_on:
        sei
        lda #0
        sta $d01a
        lda #$ff
        sta $d019
        sta sound_was
        lda SID + $18
        and #$f0
        sta SID + $18
        lda #$36
        sta $01
        rts

; Back to our own interrupts, without ROMs.
kernal_off:
        sei
        lda #$7f
        sta CIA1 + $0d
        sta CIA2 + $0d
        lda CIA1 + $0d
        lda CIA2 + $0d
        lda #$35
        sta $01
        lda #$1f
        sta SID + $18
        lda #251
        sta $d012
        lda #0
        sta irq_i
        lda #1
        sta $d01a
        sta $d019
        cli
        rts

.segment "BSS"
sound_was:  .res 1
.segment "CODE"
