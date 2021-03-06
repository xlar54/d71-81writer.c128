
// using standard kernal calls

.label buffer   = $fb  // sector buffer zero page pointer

// main entry
// carry bit is set on return if an error occurs

WRITE_71:
        jsr ENTER_D71_FILE_NAME     // ask for the filename
        jsr ULT_OPEN_FILE_READ      // attempt to open the file
        jsr DISPLAY_ULT_STATUS      // get and print status
        jsr STATUS_OK               // check status. 0=ok
        beq !+
        rts                         // abort
!:
        // ask for the device

        lda #0                  // reset device
        sta device
        ldy #1                  // permit 1 character
        jsr ENTER_DEVICE        // get destination id
        lda INPUT_BUFFER
        sec
        sbc #$30
        sta device              // store the number

        // sanity check on device

        lda device
        cmp #8
        beq !+
        cmp #9
        bne !-
!:
        // open command channel to device

        jsr COMMAND_CHANNEL_OPEN
        bcc !+
        lda #2
        sta $d020
        rts                     // abort
!:
        // Have the ultimate place the file in the REU
        // Note; reading the file using the read function seems to miss
        // every first byte on each transfer. Doing this via the REU seems to
        // work fine.

        jsr ULT_FILE_READ_REU
        jsr STATUS_OK
        beq !+
        sec                     // set carry bit to indicate problem
        rts                     // return
!:
        // Setup the REU transfer initial state

        jsr REU_SETUP_TRANSFER

        // set zero page pointer to sector buffer in ram

        lda #<sector_buffer
        sta buffer
        lda #>sector_buffer
        sta buffer+1

        // reset CMD string

        jsr RESET_SECTOR
        jsr RESET_TRACK

        // start at track 1, sector 0

        ldx #0
        stx current_sector
        inx
        stx current_track

        jsr SET_1571_MODE       // set drive in 1571 mode

        // check for fast serial

        bit SERIAL              // check bit 6
        bvs !+                  // if set, then fast serial is available
        lda #3
        sta $d020
        sec
        rts
!:
        // open buffer channel for data

        jsr BUFFER_CHANNEL_OPEN
        bcc write_d71
        lda #1
        sta $d020
        sec
        rts

        // actual write loop

write_d71:

        jsr DISPLAY_PROGRESS            // print progress string
        jsr DISPLAY_PROGRESS_HOME       // move cursor to column 0

        // get sector data from reu to memory buffer
        // 256 bytes

        jsr REU_TRANSFER_SECTOR
        jsr CHECK_BUFFER_EMPTY          // all 0's means empty sector
        bcc !+                          // carry bit clear means buffer is empty
        jsr WRITE_SECTOR                // write to disk
!:
        jsr NEXT_SECTOR                 // update command string
        inc current_sector              // update sector counter
        ldx current_track               // get index to table
        lda sectors_1571,x              // get # sectors in this track
        cmp current_sector              // all track sectors done?
        beq next_track_d71              // go to next track
        jmp write_d71                   // do next sector in this track

next_track_d71:

        // start at sector 0 in next track

        lda #0
        sta current_sector
        jsr RESET_SECTOR

        // go to next track

        jsr NEXT_TRACK                  // update command string
        inc current_track               // update track counter
        lda current_track
        cmp #71                         // all tracks done?
        bne write_d71                   // do next track
        jsr DISPLAY_DONE                // display done
        clc                             // no error
        rts

// --------------------------------------------------------------------------
// writes memory buffer to disk.
// write_track and write_sector strings need to be up to date.
// assumes channels 2 (buffer) and 15 (command) are open.

WRITE_SECTOR:
        jsr RESET_BLOCK_POINTER

        // send 256 bytes to the drive buffer.

        ldx #2
        jsr CHKOUT              // use file 2 (buffer) as output.

        ldy #0
!:
        lda (buffer),y
        jsr BSOUT
        iny
        bne !-

        // send drive buffer to disk.

        ldx #15
        jsr CHKOUT              // use file 15 (command) as output.

        ldy #0
!:
        lda u2_command,y       // read byte from command string.
        jsr BSOUT              // send to command channel.
        iny
        cpy #u2_command_end - u2_command
        bne !-

        jsr CLRCH              // execute sent command
        rts

u2_command:     .text "U2 2 0 "
write_track:    .text "01 "             // modified during write
write_sector:   .text "00"              // same
u2_command_end:

// --------------------------------------------------------------------------
// resets block pointer to position 0
// assumes channel 15 is open, and channel 2 is used for block operations

RESET_BLOCK_POINTER:
        ldx #15
        jsr CHKOUT          // use file 15 (command) as output.

        ldy #0
!loop:
        lda bp_command,y    // read byte from command string
        jsr BSOUT          // send to command channel
        iny
        cpy #bp_command_end - bp_command
        bne !loop-
        jsr CLRCH          // execute sent command
        rts

bp_command:
        .text "B-P 2 0"
bp_command_end:


// Sets 1571 drive in double sided mode

SET_1571_MODE:
        ldx #15
        jsr CHKOUT              // use file 15 (command) as output.

        ldy #0
!:
        lda ds_command,y        // read byte from command string
        jsr BSOUT               // send to command channel
        iny
        cpy #ds_command_end - ds_command
        bne !-
        jsr CLRCH               // execute sent command
        rts

ds_command:
        .text "U0>M1"
ds_command_end:



// Zero track administration. put '01' in command string.

RESET_TRACK:
        lda #$30
        sta write_track+0
        lda #$31
        sta write_track+1
        rts

// Zero sector administration. put '00' in command string.

RESET_SECTOR:
        lda #$30
        sta write_sector+0
        sta write_sector+1
        rts

// text Advance one track

NEXT_TRACK:
        inc write_track+1
        lda write_track+1
        cmp #$3a
        beq !+
        rts
!:
        inc write_track+0
        lda #$30
        sta write_track+1
        rts

// text Advance one sector

NEXT_SECTOR:
        inc write_sector+1
        lda write_sector+1
        cmp #$3a
        beq !+
        rts
!:
        inc write_sector+0
        lda #$30
        sta write_sector+1
        rts

// -------------------------------------------------

// loop counters

current_track:
        .byte 0
current_sector:
        .byte 0
device:
        .byte $09

// 1571 # of sectors per track
// sectors start at 0, tracks start at 1

sectors_1571:
        .byte 0
        // side 1, track 1
        .byte 21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21 // 17
        .byte 19,19,19,19,19,19,19 // 7
        .byte 18,18,18,18,18,18    // 6
        .byte 17,17,17,17,17       // 5
        // side 2, track 36
        .byte 21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21,21
        .byte 19,19,19,19,19,19,19
        .byte 18,18,18,18,18,18
        .byte 17,17,17,17,17

// -------------------------------------------------

.align $100      // align sector buffer to nearest page boundary

sector_buffer:
        .fill 256,$f0
