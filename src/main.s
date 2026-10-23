; main.s - Polonaise for the C64: a disco conga line in pixel art, steered like Snake.
; A port of the browser version (TypeScript) of Dennis Lehmann's Polonaise.
;
; Build: make (see Makefile). The modules are included into one assembly.

.include "defs.inc"

.import __BSS_RUN__, __BSS_SIZE__

.segment "ZEROPAGE"
ptr:        .res 2
ptr2:       .res 2

.segment "LOADADDR"
        .word $0801

.segment "EXEHDR"
        ; 10 SYS 2061
        .word @next, 10
        .byte $9e, "2061", 0
@next:  .word 0

.segment "CODE"
start:
        sei
        ldx #$ff
        txs
        lda #$36                ; BASIC off, KERNAL on
        sta $01
        ; clear the variables (BSS)
        lda #<__BSS_RUN__
        sta ptr
        lda #>__BSS_RUN__
        sta ptr + 1
        ldx #>(__BSS_SIZE__ + 255)
        ldy #0
        tya
@clr:   sta (ptr), y
        iny
        bne @clr
        inc ptr + 1
        dex
        bne @clr
        cli
        ldx $ba                 ; the drive the game came from
        cpx #8
        bcs @d
        ldx #8
@d:     stx disk_dev
        lda #0
        sta lang
        jsr load_scores
.ifdef TEST_LANG
        lda #TEST_LANG
        sta lang
.endif
        jsr sys_init
        jsr sound_init
        jsr pattern_init
        jsr fx_reset
        lda #0
        sta last_valid
        sta last_rank
        sta seed_mix
        jsr start_title
        jmp main_loop

.include "sys.s"
.include "game.s"
.include "render.s"
.include "text.s"
.include "screens.s"
.include "fx.s"
.include "sound.s"
.include "disk.s"
.ifdef TEST
.include "autopilot.s"
.endif

.segment "RODATA"
charset_data:
        .incbin "charset.bin"
sprite_data:
        .incbin "sprites.bin"
sprite_data_end:
