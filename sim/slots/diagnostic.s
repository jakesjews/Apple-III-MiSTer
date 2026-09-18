; Run on the real T65/MMU/VIAs with four synthetic cards. Slots 1/3 use
; native C02x ROM release; slots 2/4 use Apple II CFFF release.
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
.macro phase number
    lda #number
    sta $0201
.endmacro
.macro wait_count location, value
:
    lda location
    cmp #value
    bne :-
.endmacro
reset:
    sei
    cld
    ldx #$ff
    txs
    lda #$d7                  ; 1 MHz, I/O and ROM, screen off, reset enabled
    sta $ffd1
    lda #$ff
    sta $ffd3
    lda #0
    sta $ffd0
    lda #$ff
    sta $ffd2
    lda #$0f
    sta $ffe3                 ; bank bits out, individual IRQ bits in
    lda #0
    sta $ffef
    lda #$3f
    sta $ffe2
    sta $ffe0
    lda #$7f
    sta $ffde
    sta $ffee
    lda #$76                  ; SOS INT.INIT: CA1 falling edge
    sta $ffdc
    lda #0
    sta $21
    sta $22
    sta $23
    sta $24
    sta $30
    sta $31
    phase 1
    lda #$11
    sta $c090
    lda #$22
    sta $c0a0
    lda #$33
    sta $c0b0
    lda #$44
    sta $c0c0
    expect $c090, $11
    expect $c0a0, $22
    expect $c0b0, $33
    expect $c0c0, $44
    ; A slow read then two fast reads must increment exactly once apiece.
    expect $c093, 0
    lda #$57
    sta $ffdf
    expect $c093, 1
    expect $c093, 2
    inc $c090                 ; real 6502 read/old-write/new-write sequence
    expect $c090, $12
    phase 2
    bit $c020
    bit $cfff
    expect $c1ff, $5e
    expect $c800, $e1
    expect $cfff, $19          ; native card retains expansion ROM
    expect $c800, $e1
    bit $c02f
    expect $c800, $ff
    expect $c200, $a2
    expect $c800, $e2
    bit $c020                 ; Apple II card ignores native release
    expect $c800, $e2
    expect $cfff, $1a
    expect $c800, $ff
    lda #$71
    sta $c300                 ; Cnxx writes also select ROM
    lda #$93
    sta $c800
    expect $c0b4, $71
    expect $c0b5, $93
    bit $c020
    bit $c400
    expect $c800, $e4
    bit $cfff
    phase 3
    ; Hide the entire card aperture behind RAM, then restore its contents
    ; and the card's previous ROM selection. C500-C7FF is always RAM.
    bit $c100
    lda #$17
    sta $ffdf
    lda #$a5
    sta $c090
    sta $c100
    sta $c020
    sta $cfff
    lda #$5a
    sta $c500
    expect $c090, $a5
    expect $c100, $a5
    lda #$57
    sta $ffdf
    expect $c090, $12
    expect $c100, $a1
    expect $c800, $e1
    expect $c500, $5a
    bit $c020
    phase 4
    ; IRQ status is visible while the VIA interrupt is masked. Clear its
    ; flag without clearing the card, then prove a held request retriggers.
    lda #1
    sta $c091
    expect $c065, 0
    expect $c06d, 0
    expect $c064, $80
    expect $c06c, $80
    lda $ffef
    and #$b0
    cmp #$b0
    beq :+
    jmp fail
:
    jsr wait_slot_flag
    lda #2
    sta $ffdd
    jsr wait_slot_flag
    lda #$82
    sta $ffde
    cli
    wait_count $21, 1
    sei
    expect $c065, $80
    phase 5
    ; All four cards request service concurrently. Clearing one must not
    ; discard another, even after SOS-style clearing of the VIA flag.
    lda #1
    sta $c091
    sta $c0a1
    sta $c0b1
    sta $c0c1
    expect $c064, 0
    expect $c065, 0
    lda $ffef
    and #$30
    beq :+
    jmp fail
:
    cli
    wait_count $21, 2
    wait_count $22, 1
    wait_count $23, 1
    wait_count $24, 1
    sei
    expect $31, 0
    expect $c064, $80
    expect $c065, $80
    lda $ffef
    and #$30
    cmp #$30
    beq :+
    jmp fail
:
    phase 6
    ; The environmental reset lock masks CPU NMI but not the raw PB7 pin.
    lda #$47
    sta $ffdf
    lda #1
    sta $c0a2
    lda $ffe0
    and #$80
    beq :+
    jmp fail
:
    expect $30, 0
    lda #$57
    sta $ffdf
    wait_count $30, 1
    lda #1
    sta $c092
    wait_count $30, 2
    lda #1
    sta $c0b2
    wait_count $30, 3
    lda #1
    sta $c0c2
    wait_count $30, 4
    lda $ffe0
    and #$80
    bne :+
    jmp fail
:
    ; The bench exercises native Reset and Control-Reset, then lets the
    ; second pass proceed by overriding one synthetic card's scratch read.
    bit $c100
    phase 7
native_wait:
    lda $c0c0
    cmp #$99
    bne native_wait
emulation:
    phase 8
    lda #$7f
    sta $ffde
    sta $ffee
    lda #0
    sta $ffef
    lda #$4f
    sta $ffe3                 ; PA6 low enters Apple II emulation
    bit $c020
    bit $cfff
    expect $c090, $12
    expect $c300, $a3
    expect $c800, $e3
    bit $cfff                 ; native card still needs C02x in II mode
    expect $c800, $e3
    bit $c020
    expect $c800, $ff
    bit $c400
    expect $c800, $e4
    bit $cfff
    expect $c800, $ff
    lda #$5a
    sta $0200
done:
    jmp done
wait_slot_flag:
    lda $ffdd
    and #2
    beq wait_slot_flag
    rts
irq:
    pha
    lda #0
    bit $c065
    bpl irq1
    bit $c064
    bpl irq2
    lda $ffef
    and #$20
    beq irq3
    lda $ffef
    and #$10
    beq irq4
    inc $31                   ; unexpected/spurious IRQ
    jmp irq_done
irq1:
    sta $c091
    inc $21
    jmp irq_done
irq2:
    sta $c0a1
    inc $22
    jmp irq_done
irq3:
    sta $c0b1
    inc $23
    jmp irq_done
irq4:
    sta $c0c1
    inc $24
irq_done:
    lda #2
    sta $ffdd
    pla
    rti
nmi:
    pha
    inc $30
    lda #0
    sta $c092
    sta $c0a2
    sta $c0b2
    sta $c0c2
    pla
    rti
fail:
    lda #$ee
    sta $0200
    jmp fail
.res $fffa-*, $ea
.word nmi, reset, irq
