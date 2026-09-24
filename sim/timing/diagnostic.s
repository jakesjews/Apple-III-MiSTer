.setcpu "6502"
.segment "CODE"
.org $f000
.macro expect location, value
    lda location
    cmp #value
    beq :+
    jmp fail
:
.endmacro
; Ahead of the loops so their failure branches stay in range.
fail:
    lda #$ff
    sta $0200
    jmp fail
reset:
    sei
    cld
    ldx #$ff
    txs
    lda #$d7
    sta $ffd1
    lda #$ff
    sta $ffd3
    sta $ffd2
    lda #0
    sta $ffd0
    sta $0202
    lda #$7f
    sta $ffde
    sta $ffee
    ldy #0
mode:
    tya
    clc
    adc #1
    sta $0201
    lda environments,y
    sta $ffd1
    ldx #0
again:
    stx $ffdb                 ; write and read back both VIA registers
    txa
    cmp $ffdb
    bne fail
    stx $ffeb
    cmp $ffeb
    bne fail
    sta $c0f3                 ; ACIA control, including adjacent reads
    cmp $c0f3
    bne fail
    sta $c0f7                 ; and through its $C0Fx mirrors
    cmp $c0ff
    bne fail
    lda $ffd8                 ; live timer reads
    lda $ffe8
    lda $c071                 ; RTC, addressed through zero page register
    nop
    inx
    bne again
    iny
    cpy #4
    bne mode
    lda #$57
    sta $ffd1
    lda #5
    sta $0201
    expect $c090, $5a         ; held for several lines; NMI pulses during RDY
    expect $0202, 1
    expect $c090, $5a         ; exercise the remaining RDY inputs
    expect $c090, $5a
    expect $c090, $5a
    lda #$12
    sta $c090                 ; RDY low must not hold a write
    inc $c090                 ; NMOS dummy and final writes both complete
    expect $c0a0, $a5
    lda #$5a
    sta $0200
done:
    jmp done
nmi:
    inc $0202
    rti
environments:
    .byte $d7, $57, $77, $f7  ; slow/fast, screen off/on
.res $fffa-*, $ea
.word nmi, reset, nmi
