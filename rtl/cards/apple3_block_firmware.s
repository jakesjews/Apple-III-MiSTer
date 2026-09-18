; ProDOS block-mode firmware for the virtual block-storage card.
;
; The 256-byte image sits at $Cn00 in whichever slot the card occupies. It
; does not depend on the slot: the block-mode entry takes the slot from the
; unit number that every caller supplies (SOS Problock3, the soshdboot ROM,
; ProDOS 8), and the Apple II PR#n boot code recovers it from the stack.
;
; Card registers, at $C080 + slot * 16:
;   +0  read   execute the command; the card holds RDY until the result is
;              in the buffer, then returns the error code (0 = success)
;   +1  read   last error code
;   +2  write  command: 0 status, 1 read, 2 write, 3 format
;   +3  write  unit: bit 7 selects the second image
;   +4  write  block number, low byte
;   +5  write  block number, high byte
;   +6  read   block count of the selected unit, low byte
;   +7  read   block count of the selected unit, high byte
;   +8  read   next buffer byte (advances the pointer)
;   +9  write  next buffer byte (advances the pointer)
; Writing the command register rewinds the buffer pointer; completing a
; command rewinds it again. Reads never touch +9 and writes never touch +8,
; so the 6502's indexed-store dummy read cannot disturb the pointer.
;
; Assemble with cc65: ca65 apple3_block_firmware.s -o firmware.o and
; ld65 -C apple3_block_firmware.cfg firmware.o -o firmware.bin.

.setcpu "6502"
.segment "CODE"
.org $c000                       ; assembled position-independent; $Cn00 at run time

command  = $42
unit     = $43
buffer   = $44
block    = $46

card     = $c080                 ; + slot * 16 in X
execute  = card + 0
cmd_reg  = card + 2
unit_reg = card + 3
blk_lo   = card + 4
blk_hi   = card + 5
cnt_lo   = card + 6
cnt_hi   = card + 7
data_rd  = card + 8
data_wr  = card + 9

signature:
    lda #$20                     ; $Cn01 = $20
    lda #$00                     ; $Cn03 = $00
    lda #$03                     ; $Cn05 = $03
    lda #$3c                     ; $Cn07 = $3C: disk controller, not SmartPort
    ; Apple II boot (PR#n): read block 0 of drive 1 to $0800 and run it.
    ; The ROM cannot patch itself, so the call goes through the stack: the
    ; monitor RTS leaves $Cn at $0100+S, which supplies both return and
    ; entry addresses.
    jsr $ff58                    ; monitor RTS
    tsx
    lda $0100,x                  ; $Cn
    pha                          ; return address high
    lda #<(boot_return - 1)
    pha
    lda $0100,x                  ; the first push stored the same $Cn
    pha                          ; entry address high
    lda #<(entry - 1)
    pha
    lda $0100,x
    asl a
    asl a
    asl a
    asl a
    sta unit                     ; slot * 16, drive 1
    lda #$01
    sta command
    lda #$00
    sta buffer
    sta block
    sta block + 1
    lda #$08
    sta buffer + 1
    rts                          ; enters entry; its RTS comes back here
boot_return:
    bcs boot_fail
    lda unit
    tax                          ; ProDOS expects X = slot * 16
    jmp $0801
boot_fail:
    sec                          ; hold here; an absolute jump would name a slot
    bcs boot_fail

; ProDOS block-mode entry, reached through $CnFF.
entry:
    lda unit
    and #$70                     ; slot * 16 indexes the card registers
    tax
    lda command
    sta cmd_reg,x
    lda unit
    sta unit_reg,x
    lda block
    sta blk_lo,x
    lda block + 1
    sta blk_hi,x
    lda command
    cmp #$02
    beq write_block
    lda execute,x                ; RDY holds the CPU until the card is done
    bne failed
    lda command
    cmp #$01
    beq read_block
    ldy cnt_hi,x                 ; STATUS: X/Y = block count
    lda cnt_lo,x
    tax
    lda #$00
    clc
    rts

failed:
    sec
    rts

read_block:
    ldy #$00
:   lda data_rd,x
    sta (buffer),y
    iny
    bne :-
    inc buffer + 1
:   lda data_rd,x
    sta (buffer),y
    iny
    bne :-
    dec buffer + 1
    lda #$00
    clc
    rts

write_block:
    ldy #$00
:   lda (buffer),y
    sta data_wr,x
    iny
    bne :-
    inc buffer + 1
:   lda (buffer),y
    sta data_wr,x
    iny
    bne :-
    dec buffer + 1
    lda execute,x
    bne failed
    clc
    rts

.res $c0fc - *, $00
    .byte $00, $00               ; $CnFC/FD: total blocks unknown, use STATUS
    .byte $d7                    ; $CnFE: removable, interruptible, 2 volumes,
                                 ;        no format, write, read, status
    .byte <entry                 ; $CnFF: block-mode entry offset
