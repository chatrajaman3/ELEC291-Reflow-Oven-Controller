; LCD.inc
;
; Subroutines and macros for LCD display.

CSEG

; When using a 16.6MHz oscillator in the N76E003,
; one cycle takes 1.0/16.6MHz = 60.24 ns.

WAIT_40_USEC:
	PUSH AR0
	MOV R0, #133
L0:
	NOP
	DJNZ R0, L0
	POP AR0
	RET

; Toggles the 'E' pin in the LCD.

LCD_PULSE:
	SETB LCD_E
	LCALL WAIT_40_USEC
	CLR LCD_E
	RET

; Writes ACC to LCD in 4-bit mode.

LCD_BYTE:
	; Write upeer 4 bits first.
	MOV C, ACC.7
	MOV LCD_D7, C
	MOV C, ACC.6
	MOV LCD_D6, C
	MOV C, ACC.5
	MOV LCD_D5, C
	MOV C, ACC.4
	MOV LCD_D4, C
	LCALL LCD_PULSE
	LCALL WAIT_40_USEC
	; Write lower 4 bits next.
	MOV C, ACC.3
	MOV LCD_D7, C
	MOV C, ACC.2
	MOV LCD_D6, C
	MOV C, ACC.1
	MOV LCD_D5, C
	MOV C, ACC.0
	MOV LCD_D4, C
	LCALL LCD_PULSE
	RET

; Write data to LCD.

WRITEDATA MAC
	MOV A, %0
	LCALL ?WRITEDATA
ENDMAC

?WRITEDATA:
	SETB LCD_RS
	LJMP LCD_BYTE

; Write command to LCD.

WRITECOMMAND MAC
	MOV A, %0
	LCALL ?WRITECOMMAND
ENDMAC

?WRITECOMMAND:
	CLR LCD_RS
	LJMP LCD_BYTE

; Configure LCD in 4-bit mode.

LCD_INIT:
	; Resting state of LCD's enable pin is zero.
	CLR LCD_E

	; After power on, let the LCD start up before initializing.
	DELAY(#40)

	; First make sure the LCD is in 8-bit mode and then change to 4-bit mode.
	WRITECOMMAND(#0x33)
	WRITECOMMAND(#0x33)
	; Change to 4-bit mode.
	WRITECOMMAND(#0x32)

	; Configure the LCD.
	WRITECOMMAND(#0x28)
	WRITECOMMAND(#0x0C)

	; Clear screen command (takes some time).
	WRITECOMMAND(#0x01)
	; Wait for the clear screen command to finish.
	DELAY(#2)

	RET

; Send a constant string to LCD.

SEND_CONSTANT_STRING MAC
	PUSH DPH
	PUSH DPL
	PUSH ACC
	MOV DPTR, %0
	LCALL ?SEND_CONSTANT_STRING
	POP ACC
	POP DPL
	POP DPH
ENDMAC

?SEND_CONSTANT_STRING:
	CLR A
	MOVC A, @A+DPTR
	JZ ?SEND_CONSTANT_STRING_DONE
	LCALL ?WRITEDATA
	INC DPTR
	SJMP ?SEND_CONSTANT_STRING
?SEND_CONSTANT_STRING_DONE:
	RET

; Set LCD cursor at row, column.

SET_CURSOR MAC
	PUSH ACC
	MOV A, #%1
	DEC A
	LCALL ?SET_CURSOR_%0
	POP ACC
ENDMAC

?SET_CURSOR_2:
	ORL A, #0b0100_0000
?SET_CURSOR_1:
	ORL A, #0b1000_0000
	LJMP ?WRITECOMMAND

; Send a BCD number to PuTTY.

SEND_BCD MAC
	PUSH AR0
	MOV R0, %0
	LCALL ?SEND_BCD
	POP AR0
ENDMAC
?SEND_BCD:
	PUSH ACC
	; Write most significant digit.
	MOV A, R0
	SWAP A
	ANL A, #0x0F
	ORL A, #0x30
	LCALL PUTCHAR
	; write least significant digit.
	MOV A, R0
	ANL A, #0x0F
	ORL A, #0x30
	LCALL PUTCHAR
	POP ACC
	RET

; Send a character using the serial port.

PUTCHAR:
	JNB TI, PUTCHAR
	CLR TI
	MOV SBUF, A
	RET

; Display a BCD number in the LCD.

DISPLAY_BCD MAC
	PUSH AR0
	MOV R0, %0
	LCALL ?DISPLAY_BCD
	POP AR0
ENDMAC

?DISPLAY_BCD:
	PUSH ACC
	; Write most significant digit.
	MOV A, R0
	SWAP A
	ANL A, #0x0F
	ORL A, #0x30
	LCALL ?WRITEDATA
	; Write least significant digit.
	MOV A, R0
	ANL A, #0x0F
	ORL A, #0x30
	LCALL ?WRITEDATA
	POP ACC
	RET

DISPLAY_LOWER_BCD MAC
	PUSH AR0
	MOV R0, %0
	LCALL ?DISPLAY_LOWER_BCD
	POP AR0
ENDMAC

?DISPLAY_LOWER_BCD:
	PUSH ACC
	; Write least significant digit.
	MOV A, R0
	ANL A, #0x0F
	ORL A, #0x30
	LCALL ?WRITEDATA
	POP ACC
	RET

; Display a char in the LCD.

DISPLAY_CHAR MAC
	PUSH ACC
	MOV A, %0
	LCALL ?WRITEDATA
	POP ACC
ENDMAC
