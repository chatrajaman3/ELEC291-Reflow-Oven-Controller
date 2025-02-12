; util.asm
;
; Utility subroutines and macros.

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
