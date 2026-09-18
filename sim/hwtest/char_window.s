; Apple /// character-download window test: a boot block, no SOS.
;
; The ROM reads block 0 to $A000 and jumps here with interrupts off, the
; environment at $77 (2 MHz, I/O, screen, ROM), 40-column text and its own font.
;
; The scan PROM's RTCWRT reads each screen-hole byte on one blanking line:
; hole h is read on the line with V5..V3 = h, V2..V1 = V4..V3 and V0 = H2, so
; lines 192..255 visit holes 0..7 in order and 254..255 repeat hole 7.  Hole h
; carries font rows 2 x (h mod 4) and 2 x (h mod 4) + 1.
;
; Code $02 is loaded over a whole blanking interval with rows 4 and 5 blank:
; the reference.  Code $01 is loaded blank the same way, then every hole is
; made solid and $C0DB is switched on only from about line 217 to about line
; 240.  That window reads holes 3, 4 and 5 (rows 6-7, 0-1 and 2-3) and misses
; holes 2 and 6 (rows 4-5), so the test glyph must match the reference.  A
; blank test row means downloads happened all at once outside the window; a
; solid one means they ignored the window.

        .setcpu "6502"

ENV     = $FFDF         ; D VIA port A: environment register
E_PCR   = $FFEC         ; E VIA peripheral control
E_IFR   = $FFED         ; E VIA interrupt flags, bit 3 = CB2 (vertical blanking)

; Text rows in page 1: $0400 + (row mod 8) x $80 + (row / 8) x 40.
ROW1    = $0400 + 1 * $80
ROW5    = $0400 + 5 * $80
ROW7    = $0400 + 7 * $80
ROW11   = $0400 + 3 * $80 + 40
ROW13   = $0400 + 5 * $80 + 40
ROW18   = $0400 + 2 * $80 + 80

; Screen holes of text rows 0..7 in page 1; the page 2 sister is $400 above.
HOLE0   = $0478
HOLE1   = $04F8
HOLE2   = $0578
HOLE3   = $05F8
HOLE4   = $0678
HOLE5   = $06F8
HOLE6   = $0778
HOLE7   = $07F8

        .segment "CODE"

start:  sei
        cld
        ldx #$FF
        txs
        lda #$F7                ; the ROM's $77 plus bit 7: 1 MHz, one state per cycle
        sta ENV
        lda $C050               ; VM0..VM3 clear: 40-column text, page 1
        lda $C052
        lda $C054
        lda $C056
        lda $C0D8               ; smooth scroll off
        lda $C0DA               ; character download off
        lda E_PCR
        and #$1F
        ora #$60                ; CB2: independent input, positive edge (start of VBL)
        sta E_PCR

        lda #$A0                ; clear text page 1 to spaces
        ldx #0
clear:  sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        inx
        bne clear

        ldx #0
title:  lda msg_title,x
        beq :+
        ora #$80
        sta ROW1+5,x
        inx
        bne title
:       ldx #0
ref:    lda msg_ref,x
        beq :+
        ora #$80
        sta ROW5+2,x
        inx
        bne ref
:       ldx #0
test:   lda msg_test,x
        beq :+
        ora #$80
        sta ROW11+2,x
        inx
        bne test
:       ldx #0
pass:   lda msg_pass,x
        beq :+
        ora #$80
        sta ROW18+2,x
        inx
        bne pass
:
        ldx #39                 ; normal-video rows of the two glyphs
glyphs: lda #$82
        sta ROW7,x
        lda #$81
        sta ROW13,x
        dex
        bpl glyphs

        lda #$02                ; reference: rows 4 and 5 blank
        ldx #0
        jsr holes
        jsr wholevbl
        lda #$01                ; test glyph starts blank
        ldx #8
        jsr holes
        jsr wholevbl
        lda #$01                ; then solid in every hole, inside the window only
        ldx #16
        jsr holes
        jsr waitvbl             ; line 192
        ldy #25
        jsr lines               ; about line 217: after hole 2 (213), before hole 3 (222)
        lda $C0DB
        ldy #23
        jsr lines               ; about line 240: after hole 5 (235), before hole 6 (244)
        lda $C0DA
halt:   jmp halt

; A = character code, X = row pattern (0, 8 or 16): code in all 64 page 2
; hole bytes, and that pattern's row value for each hole in page 1.
holes:  ldy #7
hc:     sta HOLE0+$400,y
        sta HOLE1+$400,y
        sta HOLE2+$400,y
        sta HOLE3+$400,y
        sta HOLE4+$400,y
        sta HOLE5+$400,y
        sta HOLE6+$400,y
        sta HOLE7+$400,y
        dey
        bpl hc
        ldy #7
hb:     lda patterns+0,x
        sta HOLE0,y
        lda patterns+1,x
        sta HOLE1,y
        lda patterns+2,x
        sta HOLE2,y
        lda patterns+3,x
        sta HOLE3,y
        lda patterns+4,x
        sta HOLE4,y
        lda patterns+5,x
        sta HOLE5,y
        lda patterns+6,x
        sta HOLE6,y
        lda patterns+7,x
        sta HOLE7,y
        dey
        bpl hb
        rts

; $C0DB on across one complete blanking interval, as the ROM loads its font.
wholevbl:
        lda $C0DB
        jsr waitvbl
        jsr waitvbl
        lda $C0DA
        rts

; Return within a few cycles of the start of vertical blanking.
waitvbl:
        lda #$08
        sta E_IFR
:       lda E_IFR
        and #$08
        beq :-
        rts

; Wait Y scan lines: 65 cycles per pass at 1 MHz.
lines:  ldx #11                 ; 2
:       dex                     ; 2
        bne :-                  ; 3, 2 on exit: 54
        nop                     ; 2
        nop                     ; 2
        dey                     ; 2
        bne lines               ; 3
        rts

; Row value per hole (hole h holds rows 2 x (h mod 4) and the one after).
patterns:
        .byte $7F, $7F, $00, $7F, $7F, $7F, $00, $7F   ; reference: rows 4-5 blank
        .byte $00, $00, $00, $00, $00, $00, $00, $00   ; blank
        .byte $7F, $7F, $7F, $7F, $7F, $7F, $7F, $7F   ; solid

msg_title:  .byte "CHARACTER DOWNLOAD WINDOW TEST", 0
msg_ref:    .byte "REFERENCE, LOADED OVER A WHOLE VBL:", 0
msg_test:   .byte "TEST, $C0DB ON FOR LINES 217-240:", 0
msg_pass:   .byte "PASS: BOTH ROWS MATCH, WITH A GAP.", 0
