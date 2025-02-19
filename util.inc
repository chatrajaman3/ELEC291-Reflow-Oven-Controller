; util.asm
;
; Utility subroutines and macros.

; Read/write to flash storage using IAP.

IAP_WRITE_REG MAC REG
	MOV IAPCN, #0b0010_0001
	MOV IAPFD, %0

	; Begin IAP.
	MOV TA, #0xAA
	MOV TA, #0x55
	ORL IAPTRG, #0b0000_0001

	INC IAPAL
ENDMAC

IAP_READ_ADDR MAC REG
	MOV A, #0x00
	MOVC A, @A+DPTR
	MOV %0, A

	INC DPTR
ENDMAC

; Write R0-R7 from banks 1-2 into APROM starting at address 0x400.
IAP_WRITE:
	PUSH PSW

	; Disable interrupts to avoid delays when writing to
	; timed access registers.
	CLR EA

	; Enable IAP function.
	MOV TA, #0xAA
	MOV TA, #0x55
	ORL CHPCON, #0b0000_0001

	; Enable APROM erasing and programming by IAP.
	MOV TA, #0xAA
	MOV TA, #0x55
	ORL IAPUEN, #0b0000_0001

	; Erase page 0x400~0x47F.
	MOV IAPCN, #0b0010_0010
	MOV IAPAH, #0x04
	MOV IAPAL, #0x00
	MOV IAPFD, #0xFF

	; Begin IAP.
	MOV TA, #0xAA
	MOV TA, #0x55
	ORL IAPTRG, #0b0000_0001

	; Note: ANL/ORL PSW will break the program. We need to MOV
	; the register banks directly here.

	; Switch to register bank 1.
	MOV PSW, #0b0000_1000

	IAP_WRITE_REG(R0)
	IAP_WRITE_REG(R1)
	IAP_WRITE_REG(R2)
	IAP_WRITE_REG(R3)
	IAP_WRITE_REG(R4)
	IAP_WRITE_REG(R5)
	IAP_WRITE_REG(R6)
	IAP_WRITE_REG(R7)

	; Switch to register bank 2.
	MOV PSW, #0b0001_0000

	IAP_WRITE_REG(R0)
	IAP_WRITE_REG(R1)
	IAP_WRITE_REG(R2)
	IAP_WRITE_REG(R3)
	IAP_WRITE_REG(R4)
	IAP_WRITE_REG(R5)
	IAP_WRITE_REG(R6)
	IAP_WRITE_REG(R7)

	; Write signature to 0x47F
	MOV IAPCN, #0b0010_0001
	MOV IAPAH, #0x04
	MOV IAPAL, #0x7F
	MOV IAPFD, #SIGNATURE

	; Begin IAP.
	MOV TA, #0xAA
	MOV TA, #0x55
	ORL IAPTRG, #0b0000_0001

	; Disable APROM erasing and programming by IAP.
	MOV TA, #0xAA
	MOV TA, #0x55
	ANL IAPUEN, #0b1111_1110

	; Disable IAP function.
	MOV TA, #0xAA
	MOV TA, #0x55
	ANL CHPCON, #0b1111_1110

	; Reenable global interrupts.
	SETB EA

	; Restores register bank to its state before the subroutine call.
	POP PSW
	RET

; Reads data from APROM starting at address 0x400 and stores
; it into R0-R7 of banks 1-2.
IAP_READ:
	PUSH ACC
	PUSH PSW
	MOV DPTR, #0x400

	; Switch to register bank 1.
	ANL PSW, #0b1110_0111
	ORL PSW, #0b0000_1000

	IAP_READ_ADDR(R0)
	IAP_READ_ADDR(R1)
	IAP_READ_ADDR(R2)
	IAP_READ_ADDR(R3)
	IAP_READ_ADDR(R4)
	IAP_READ_ADDR(R5)
	IAP_READ_ADDR(R6)
	IAP_READ_ADDR(R7)

	; Switch to register bank 2.
	ANL PSW, #0b1110_0111
	ORL PSW, #0b0001_0000

	IAP_READ_ADDR(R0)
	IAP_READ_ADDR(R1)
	IAP_READ_ADDR(R2)
	IAP_READ_ADDR(R3)
	IAP_READ_ADDR(R4)
	IAP_READ_ADDR(R5)
	IAP_READ_ADDR(R6)
	IAP_READ_ADDR(R7)

	; Restores register bank to its state before the subroutine call.
	POP PSW
	POP ACC
	RET

; Delay subroutines and macros.

DELAY MAC MS
	PUSH AR2
	MOV R2, %0
	LCALL WAIT_MS
	POP AR2
ENDMAC

WAIT_1_MS:
	; Stop timer 0.
	CLR TR0
	; Clear overflow flag.
	CLR TF0
	MOV TH0, #HIGH(TIMER0_RELOAD)
	MOV TL0, #LOW(TIMER0_RELOAD)
	SETB TR0
	; Wait for overflow.
	JNB TF0, $
	RET

; Wait the number of milliseconds in R2.
WAIT_MS:
	LCALL WAIT_1_MS
	DJNZ R2, WAIT_MS
	RET
