; Exercise the block card's firmware on the real CPU, the way SOS's Problock3
; driver and the soshdboot ROM do: find the signature, call the $CnFF entry
; with the ProDOS parameters, and check every result. The bench mounts two
; images and inspects the host images after each write.
.setcpu "6502"
.segment "CODE"
.org $f000
.macro phase number
    lda #number
    sta $0201
.endmacro
.macro fail_if_ne
    beq :+
    jmp fail
:
.endmacro
.macro fail_if_cs
    bcc :+
    jmp fail
:
.endmacro
.macro fail_if_cc
    bcs :+
    jmp fail
:
.endmacro
.macro expect_error code
    fail_if_cc
    cmp #code
    fail_if_ne
.endmacro

command = $42
unit    = $43
buffer  = $44
block   = $46
entry   = $48                     ; entry pointer patched from $CnFF
scratch = $4a
slot    = $4c

reset:
    sei
    cld
    ldx #$ff
    txs
    lda #$d7                      ; 1 MHz, I/O and ROM enabled, screen off
    sta $ffd1
    lda #$ff
    sta $ffd3
    lda #0
    sta $ffd0
    lda #$ff
    sta $ffd2
    lda #$0f
    sta $ffe3
    lda #0
    sta $ffef
    lda #$3f
    sta $ffe2
    sta $ffe0
    lda #$7f
    sta $ffde
    sta $ffee

    ; Phase 1: scan slots 4 to 1 for the block signature like Problock3.
    phase 1
    lda #$c4
    sta scratch+1
    lda #0
    sta scratch
scan:
    ldy #5
:   lda (scratch),y
    cmp signature,y
    bne next_slot
    dey
    dey
    bpl :-
    ldy #$ff
    lda (scratch),y
    beq next_slot
    cmp #$ff
    beq next_slot
    sta entry
    lda scratch+1
    sta entry+1
    and #7
    sta slot
    jmp found
next_slot:
    dec scratch+1
    lda scratch+1
    and #7
    bne scan
    jmp fail
found:
    lda slot
    cmp #1                        ; the bench installs the card in slot 1
    fail_if_ne
    lda $c1fe
    cmp #$d7
    fail_if_ne

    ; Phase 2: STATUS of both drives (drive 1: 40 blocks, drive 2: 24).
    phase 2
    lda #0
    sta command
    lda #$10
    sta unit
    jsr call
    fail_if_cs
    cpx #40
    fail_if_ne
    cpy #0
    fail_if_ne
    lda #$90
    sta unit
    jsr call
    fail_if_cs
    cpx #24
    fail_if_ne
    cpy #0
    fail_if_ne

    ; Phase 3: read block 7 of drive 1 into $2000 and check the pattern
    ; (byte i of block b is b * 17 + i * 3).
    phase 3
    lda #1
    sta command
    lda #$10
    sta unit
    lda #0
    sta buffer
    sta block+1
    lda #$20
    sta buffer+1
    lda #7
    sta block
    jsr call
    fail_if_cs
    lda buffer+1
    cmp #$20                      ; the firmware restores the pointer
    fail_if_ne
    lda #7
    jsr check_pattern

    ; Phase 4: write block 5 of drive 1 from a filled buffer, read it back.
    phase 4
    lda #$21
    sta buffer+1
    ldy #0
:   tya
    eor #$5a
    sta $2100,y
    tya
    eor #$a5
    sta $2200,y
    iny
    bne :-
    lda #2
    sta command
    lda #5
    sta block
    jsr call
    fail_if_cs
    lda #4
    sta $0202                     ; bench: host block 5 must hold the pattern
    lda #1
    sta command
    lda #$23
    sta buffer+1
    jsr call
    fail_if_cs
    ldy #0
verify_5:
    lda $2300,y
    cmp $2100,y
    fail_if_ne
    lda $2400,y
    cmp $2200,y
    fail_if_ne
    iny
    bne verify_5

    ; Phase 5: drive 2 is protected; read works, write and format fail.
    phase 5
    lda #$90
    sta unit
    lda #3
    sta block
    lda #1
    sta command
    lda #$20
    sta buffer+1
    jsr call
    fail_if_cs
    lda #3
    jsr check_pattern2
    lda #2
    sta command
    jsr call
    expect_error $2b
    lda #3
    sta command
    jsr call
    expect_error $2b
    lda #3
    sta command
    lda #$10
    sta unit
    jsr call
    fail_if_cs

    ; Phase 6: block past the end, then unmounted drive 2.
    phase 6
    lda #1
    sta command
    lda #40
    sta block
    jsr call
    expect_error $27
    lda #2
    sta command
    jsr call
    expect_error $27
    lda #0
    sta block
    lda #6
    sta $0202                     ; bench: unmount drive 2
    lda #0
    sta command
    lda #$90
    sta unit
    jsr call
    expect_error $28
    lda #1
    sta command
    jsr call
    expect_error $28

    ; Phase 7: read block 39 with the bank register pointing elsewhere; the
    ; buffer at $8000 lands in the selected bank, as Problock3 arranges.
    phase 7
    lda #$0f
    sta $ffe3
    lda #3
    sta $ffef
    lda #1
    sta command
    lda #$10
    sta unit
    lda #39
    sta block
    lda #$00
    sta buffer
    lda #$80
    sta buffer+1
    jsr call
    fail_if_cs
    lda #39
    jsr check_pattern
    lda #0
    sta $ffef

    lda #$5a
    sta $0200                     ; success
halt:
    jmp halt

fail:
    lda #$ee
    sta $0200
    jmp halt

; A = block number; the block was read to (buffer). Byte i of drive 1's
; block b is b * 17 + i * 3, kept as a running value.
check_pattern:
    sta scratch
    asl a
    asl a
    asl a
    asl a
    clc
    adc scratch
    sta scratch
    ldy #0
@low:
    lda (buffer),y
    cmp scratch
    fail_if_ne
    lda scratch
    clc
    adc #3
    sta scratch
    iny
    bne @low
    inc buffer+1
@high:
    lda (buffer),y
    cmp scratch
    fail_if_ne
    lda scratch
    clc
    adc #3
    sta scratch
    iny
    bne @high
    dec buffer+1
    rts

; Drive 2: byte i of block b is b * 5 + i.
check_pattern2:
    sta scratch
    asl a
    asl a
    clc
    adc scratch
    sta scratch
    ldy #0
@low:
    lda (buffer),y
    cmp scratch
    fail_if_ne
    inc scratch
    iny
    bne @low
    inc buffer+1
@high:
    lda (buffer),y
    cmp scratch
    fail_if_ne
    inc scratch
    iny
    bne @high
    dec buffer+1
    rts

call:
    jmp (entry)

signature:
    .byte $ff, $20, $ff, $00, $ff, $03

.res $fffa - *, $ea
    .word reset
    .word reset
    .word reset
