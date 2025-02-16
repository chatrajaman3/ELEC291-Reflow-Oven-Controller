; main.asm
;
; Assembly code for reflow oven controller.
; Written for N76E003 (8051 derivative).
;
; Authored by Eric Feng, Warrick Lo, Santo Neyyan,
; Chathil Rajamanthree, Rishi Upath, Colin Yeung.

; N76E003 pinout
;                                              -------
; [ADC push button]    PWM2/IC6/T0/AIN4/P0.5 -|1    20|- P0.4/AIN5/STADC/PWM3/IC3
; [USB]                        TXD/AIN3/P0.6 -|2    19|- P0.3/PWM5/IC5/AIN6
; [USB]                        RXD/AIN2/P0.7 -|3    18|- P0.2/ICPCK/OCDCK/RXD_1/[SCL]
; [RESET for MC]                    RST/P2.0 -|4    17|- P0.1/PWM4/IC4/MISO
; [Ambient temp]        INT0/OSCIN/AIN1/P3.0 -|5    16|- P0.0/PWM3/IC3/MOSI/T1
; [LM4040 temp ref]           INT1/AIN0/P1.7 -|6    15|- P1.0/PWM2/IC2/SPCLK          [PWM output]
;                                        GND -|7    14|- P1.1/PWM1/IC1/AIN7/CLO       [Analog OPAMP input]
; [Oven on/off] [SDA]/TXD_1/ICPDA/OCDDA/P1.6 -|8    13|- P1.2/PWM0/IC0                [Speaker output]
;                                        VDD -|9    12|- P1.3/SCL/[STADC]
; [SHIFT button]            PWM5/IC7/SS/P1.5 -|10   11|- P1.4/SDA/FB/PWM1
;                                              -------

; ADC channel mappings.
;
; AIN0	P1.7	Reference voltage
; AIN1	P3.0	Ambient temperature
; AIN4	P0.5	Push button
; AIN7	P1.1	Op-amp with thermocouple wire

; Mappings for push buttons.
;
; P1.5	SHIFT modifier
; P1.6	Start/stop oven
;
; PB.0	Load preset 4
; PB.1	Load preset 3
; PB.2	Load preset 2
; PB.3	Load preset 1
; PB.4	Reflow time
; PB.5	Reflow temperature
; PB.6	Soak time
; PB.7	Soak temperature

$NOLIST
$MODN76E003
$LIST

ORG 0x0000
	LJMP START

; Timer 2 ISR vector.
ORG 0x002B
	LJMP TIMER2_ISR

; Timer 3 ISR vector.
ORG 0x0083
	LJMP TIMER3_ISR

; 0b0101_1010.
SIGNATURE EQU 0x5A

; Microcontroller system frequency in Hz.
CLK EQU 16600000
; Baud rate of UART in bit/s.
BAUD EQU 115200
; Timer reload values.
TIMER0_RELOAD EQU (0x10000 - (CLK/1000))
TIMER1_RELOAD EQU (0x100 - (CLK/(16*BAUD)))
TIMER2_RELOAD EQU (0x10000 - (CLK/1600))
TIMER3_RELOAD EQU (0x10000 - (CLK/2000))

; PWM.
PWM_OUT EQU P1.0
; Speaker output.
SPKR_OUT EQU P1.2
; Start/stop oven.
OVEN_BUTTON EQU P1.6
; Shift button.
S_BUTTON EQU P1.5

; LCD I/O pins.
LCD_E EQU P1.4
LCD_RS EQU P1.3
LCD_D4 EQU P0.0
LCD_D5 EQU P0.1
LCD_D6 EQU P0.2
LCD_D7 EQU P0.3

; State machine states representations.
STATE_INIT EQU 0
STATE_IDLE EQU 1
STATE_PREHEAT EQU 2
STATE_SOAK EQU 3
STATE_RAMP EQU 4
STATE_REFLOW EQU 5
STATE_COOLING EQU 6
STATE_EMERGENCY EQU 7

$NOLIST
$include(util.inc)
$include(LCD.inc)
$include(math32.inc)
$LIST

DSEG at 0x20

; Bitfield for push button values.
PB: DS 1

DSEG at 0x30

counter: DS 1

; State machine related variables. Refer to defined macros.
time: DS 2
counter_ms: DS 2
FSM1_state: DS 1

; Variables for 32-bit integer arithmetic.
x: DS 4
y: DS 4
z: DS 4

; User-controlled variables.
soak_temp: DS 1
soak_time: DS 1
reflow_temp: DS 1
reflow_time: DS 1

; Reference voltage.
VAL_LM4040: DS 2
; Ambient temperature.
VAL_LM335: DS 2

; Oven controller variables.
pwm: DS 1
temp_oven: DS 2

; BCD numbers for LCD.
bcd: DS 5

BSEG

mf: DBIT 1
spkr_disable: DBIT 1

CSEG

; LCD display strings.

temp:
	DB '   C/  C    :  s', 0
str_soak_params:
	DB 'SOAK       C   s', 0
str_reflow_params:
	DB 'REFLOW     C   s', 0
str_target:
	DB 'Target:', 0
str_preheat:
	DB 'PRE ', 0
str_soak:
	DB 'SOAK', 0
str_ramp:
	DB 'RAMP', 0
str_reflow:
	DB 'RFLW', 0
str_cooling:
	DB 'COOLING DOWN', 0
str_emergency_1:
	DB 'EMERGENCY ABORT', 0
str_emergency_2:
	DB 'CHECK THERMOWIRE', 0
str_abort:
	DB 'Aborting...', 0

; Interrupt service routines.

TIMER2_ISR:
	PUSH ACC
	PUSH PSW
	; Reset timer 2 overflow flag.
	CLR TF2

	; PWM.
	CLR C
	INC counter
	MOV A, pwm
	SUBB A, counter
	MOV PWM_OUT, C

	MOV A, counter
	CJNE A, #100, TIMER2_ISR_L1

	; Executes every second.
	MOV counter, #0
	; Increment 1 s counter.
	MOV A, time+0
	ADD A, #1
	DA A
	MOV time+0, A
	CJNE A, #0x60, TIMER2_ISR_L1
	; Reset 1 s counter.
	MOV time+0, #0x00
	; Increment 1 min counter.
	MOV A, time+1
	ADD A, #1
	DA A
	MOV time+1, A
TIMER2_ISR_L1:
	POP PSW
	POP ACC
	RETI

TIMER3_ISR:
	JB spkr_disable, TIMER3_ISR_L1
	CPL SPKR_OUT
TIMER3_ISR_L1:
	RETI

; Program entry point.

START:
	MOV SP, #0x7FH

	; Configure all the pins for biderectional I/O.
	MOV P3M1, #0x00
	MOV P3M2, #0x00
	MOV P1M1, #0x00
	MOV P1M2, #0x00
	MOV P0M1, #0x00
	MOV P0M2, #0x00

	; Enable global interrupts.
	SETB EA

	; CLK is the input for timer 1.
	ORL CKCON, #0b0001_0000
	; Bit SMOD=1, double baud rate.
	ORL PCON, #0b1000_0000
	MOV SCON, #0b0101_0010
	ANL T3CON, #0b1101_1111
	; Clear the configuration bits for timer 1.
	ANL TMOD, #0b0000_1111
	; Timer 1 Mode 2.
	ORL TMOD, #0b0010_0000
	; TH1 = TIMER1_RELOAD.
	MOV TH1, #TIMER1_RELOAD
	SETB TR1

	; Initialise temperatures/times.
	MOV soak_temp, #0x50
	MOV soak_time, #0x75
	MOV reflow_temp, #0x25
	MOV reflow_time, #0x60

	; Using timer 0 for delay functions.
	CLR TR0
	ORL CKCON, #0b0000_1000
	ANL TMOD, #0b1111_0000
	ORL TMOD, #0b0000_0001

	; Timer 2 initialisation.
	MOV T2CON, #0b0000_0000
	MOV T2MOD, #0b1010_0000
	ORL EIE, #0b1000_0000
	MOV TH2, #HIGH(TIMER2_RELOAD)
	MOV TL2, #LOW(TIMER2_RELOAD)
	MOV RCMP2H, #HIGH(TIMER2_RELOAD)
	MOV RCMP2L, #LOW(TIMER2_RELOAD)
	MOV counter, #0x00
	SETB TR2

	; Timer 3 initialisation.
	MOV RH3, #HIGH(TIMER3_RELOAD)
	MOV RL3, #LOW(TIMER3_RELOAD)
	ORL EIE1, #0b0000_0010
	MOV T3CON, #0b0000_1000

	; Initialize and start the ADC.

	; Configure AIN4 (P0.5) as input.
	ORL P0M1, #0b0010_0000
	ANL P0M2, #0b1101_1111
	; Configure AIN0 (P1.7) and AIN7 (P1.1) as input.
	ORL P1M1, #0b1000_0010
	ANL P1M2, #0b0111_1101
	; Configure AIN1 (P3.0) as input.
	ORL P3M1, #0b0000_0001
	ANL P3M2, #0b1111_1110
	; Set AIN0, AIN1, AIN4, and AIN7 as analog inputs.
	ORL AINDIDS, #0b1001_0011
	; Enable ADC.
	ORL ADCCON1, #0b0000_0001

	LCALL LCD_INIT

	; Check flash memory for the program's signature so we
	; can initialise the APROM on first boot.
	PUSH ACC
	MOV DPTR, #0x47F
	MOV A, #0x00
	MOVC A, @A+DPTR
	CJNE A, #SIGNATURE, $+5
	SJMP $+5
	LCALL APROM_INIT
	; LJMP $+3
	POP ACC

	WRITECOMMAND(#0x40)

	; Arrow.
	WRITEDATA(#0b00000)
	WRITEDATA(#0b01000)
	WRITEDATA(#0b01100)
	WRITEDATA(#0b00110)
	WRITEDATA(#0b00110)
	WRITEDATA(#0b01100)
	WRITEDATA(#0b01000)
	WRITEDATA(#0b00000)

	; Initialise state machine.
	MOV FSM1_state, #STATE_IDLE
	MOV time+0, #0x00
	MOV time+1, #0x00
	SETB spkr_disable

	; Speaker output.

	SET_CURSOR(1, 1)
	SEND_CONSTANT_STRING(#str_soak_params)
	SET_CURSOR(2, 1)
	SEND_CONSTANT_STRING(#str_reflow_params)

	; ; Create 1 custom character for the LCD.
	; MOV A, #0x08

	; End of initialisation. Output 55AA to serial port.
	PUSH ACC
	MOV A, #'5'
	LCALL PUTCHAR
	LCALL PUTCHAR
	MOV A, #'A'
	LCALL PUTCHAR
	LCALL PUTCHAR
	MOV A, #'\r'
	LCALL PUTCHAR
	MOV A, #'\n'
	LCALL PUTCHAR
	POP ACC

MAIN:
	MOV A, FSM1_state
	LJMP IDLE

; Begin state machine logic and handling.

EMERGENCY:
	SET_CURSOR(1, 1)
	SEND_CONSTANT_STRING(#str_emergency_1)
	SET_CURSOR(2, 1)
	SEND_CONSTANT_STRING(#str_emergency_2)
	; Check if oven on/off button is pressed.
	JB OVEN_BUTTON, EMERGENCY_L1
	DELAY(#100)
	JB OVEN_BUTTON, EMERGENCY_L1
	JNB OVEN_BUTTON, $
	LJMP RESET_TO_IDLE
EMERGENCY_L1:
	LJMP MAIN

OVEN_ON:
	; This delay helps mitigate an undesired flash at
	; the beginning of the state transition.
	DELAY(#5)

	CJNE A, #STATE_EMERGENCY, $+6
	LJMP EMERGENCY

	SET_CURSOR(1, 1)
	SEND_CONSTANT_STRING(#temp)
	LCALL READ_TEMP
	SET_CURSOR(1, 12)
	DISPLAY_LOWER_BCD(time+1)
	SET_CURSOR(1, 14)
	DISPLAY_BCD(time+0)
	DELAY(#250)
	DELAY(#250)

	; Check if oven on/off button is pressed.
	JB OVEN_BUTTON, OVEN_ON_L1
	DELAY(#75)
	JB OVEN_BUTTON, OVEN_ON_L1
	JNB OVEN_BUTTON, $

	; Abort reflow process.
	WRITECOMMAND(#0x01)
	DELAY(#5)
	SEND_CONSTANT_STRING(#str_abort)
	LJMP RESET_TO_IDLE

OVEN_ON_L1:
	LJMP PREHEAT

OVEN_ON_INTERIM:
	LJMP OVEN_ON

IDLE:
	CJNE A, #STATE_IDLE, OVEN_ON_INTERIM
	MOV pwm, #0

	; Convert ADC signal to push button bitfield.
	LCALL ADC_TO_PB

	; Go to handler subroutines if button is pressed.

	; Shift button is handled inside the subroutine.
	JB PB.4, $+6
	LCALL CHANGE_REFLOW_TIME
	JB PB.5, $+6
	LCALL CHANGE_REFLOW_TEMP
	JB PB.6, $+6
	LCALL CHANGE_SOAK_TIME
	JB PB.7, $+6
	LCALL CHANGE_SOAK_TEMP

	; Check if SHIFT+PB.{0..3} is pressed.
	JB S_BUTTON, IDLE_L1

	JB PB.0, $+6
	LCALL SAVE_PRESET_4
	JB PB.1, $+6
	LCALL SAVE_PRESET_3
	JB PB.2, $+6
	LCALL SAVE_PRESET_2
	JB PB.3, $+6
	LCALL SAVE_PRESET_1

IDLE_L1:
	JB PB.0, $+6
	LCALL LOAD_PRESET_4
	JB PB.1, $+6
	LCALL LOAD_PRESET_3
	JB PB.2, $+6
	LCALL LOAD_PRESET_2
	JB PB.3, $+6
	LCALL LOAD_PRESET_1

	LJMP DISPLAY_VARIABLES

DISPLAY_VARIABLES:
	; Display variables.
	SET_CURSOR(1, 9)
	DISPLAY_CHAR(#'1')
	DISPLAY_BCD(soak_temp)
	SET_CURSOR(1, 14)
	DISPLAY_BCD(soak_time)
	SET_CURSOR(2, 9)
	DISPLAY_CHAR(#'2')
	DISPLAY_BCD(reflow_temp)
	SET_CURSOR(2, 14)
	DISPLAY_BCD(reflow_time)

	; Check if oven on/off button is pressed.
	JB OVEN_BUTTON, IDLE_L2
	DELAY(#100)
	JB OVEN_BUTTON, IDLE_L2
	JNB OVEN_BUTTON, $

PREHEAT_TRANSITION:
	WRITECOMMAND(#0x01)
	CLR spkr_disable
	DELAY(#250)
	SETB spkr_disable
	MOV FSM1_state, #STATE_PREHEAT
	MOV time+0, #0x00
	MOV time+1, #0x00
	MOV pwm, #100

IDLE_L2:
	DELAY(#100)
	LJMP MAIN

SOAK_INTERIM:
	LJMP SOAK

PREHEAT:
	CJNE A, #STATE_PREHEAT, SOAK_INTERIM

	SET_CURSOR(2, 1)
	SEND_CONSTANT_STRING(#str_preheat)
	SET_CURSOR(2, 6)
	SEND_CONSTANT_STRING(#str_target)
	SET_CURSOR(2, 13)
	DISPLAY_CHAR(#'1')
	DISPLAY_BCD(soak_temp)
	DISPLAY_CHAR(#'C')

	; Check if oven temperature reaches 50 deg C within 60 s.
	MOV A, time+1
	JNZ $+4
	SJMP PREHEAT_L1
	MOV A, temp_oven+1
	CJNE A, #0x00, PREHEAT_L1
	CLR C
	MOV A, #0x50
	SUBB A, temp_oven+0
	JC PREHEAT_L1
ABORTING:
	WRITECOMMAND(#0x01)
	MOV FSM1_state, #STATE_EMERGENCY
	MOV pwm, #0
	SET_CURSOR(1, 1)
	SEND_CONSTANT_STRING(#str_abort)
	CLR spkr_disable
	DELAY(#250)
	DELAY(#250)
	DELAY(#250)
	DELAY(#250)
	SETB spkr_disable
	LJMP MAIN

PREHEAT_L1:
	; Check if oven temperature is more than threshold.
	CLR C
	MOV A, temp_oven+1
	SUBB A, #0x01
	JC PREHEAT_L2
	MOV A, temp_oven+0
	SUBB A, soak_temp
	JC PREHEAT_L2

SOAK_TRANSITION:
	WRITECOMMAND(#0x01)
	CLR spkr_disable
	DELAY(#250)
	SETB spkr_disable
	MOV FSM1_state, #STATE_SOAK
	MOV time+0, #0x00
	MOV time+1, #0x00
	MOV pwm, #20

PREHEAT_L2:
	LJMP MAIN

RAMPUP_INTERIM:
	LJMP RAMPUP

SOAK:
	CJNE A, #STATE_SOAK, RAMPUP_INTERIM

	SET_CURSOR(2, 1)
	SEND_CONSTANT_STRING(#str_soak)
	SET_CURSOR(2, 6)
	SEND_CONSTANT_STRING(#str_target)
	SET_CURSOR(2, 14)
	DISPLAY_BCD(soak_time)
	DISPLAY_CHAR(#'s')

	CLR C
	MOV A, soak_time
	SUBB A, #0x60
	JC SOAK_L1
	; Target soak time here is equal or more than 60 s.
	MOV R0, A
	MOV A, time+1
	CJNE A, #1, SOAK_L3
	SJMP SOAK_L2
SOAK_L1:
	MOV R0, soak_time
SOAK_L2:
	CLR C
	MOV A, time+0
	SUBB A, R0
	JC SOAK_L3

RAMP_TRANSITION:
	WRITECOMMAND(#0x01)
	CLR spkr_disable
	DELAY(#250)
	SETB spkr_disable
	MOV FSM1_state, #STATE_RAMP
	MOV time+0, #0x00
	MOV time+1, #0x00
	MOV pwm, #100

SOAK_L3:
	LJMP MAIN

REFLOW_INTERIM:
	LJMP REFLOW

RAMPUP:
	CJNE A, #STATE_RAMP, REFLOW_INTERIM

	SET_CURSOR(2, 1)
	SEND_CONSTANT_STRING(#str_ramp)
	SET_CURSOR(2, 6)
	SEND_CONSTANT_STRING(#str_target)
	SET_CURSOR(2, 13)
	DISPLAY_CHAR(#'2')
	DISPLAY_BCD(reflow_temp)
	DISPLAY_CHAR(#'C')

	CLR C
	MOV A, temp_oven+1
	SUBB A, #0x02
	JC RAMPUP_L1
	MOV A, temp_oven+0
	SUBB A, reflow_temp
	JC RAMPUP_L1

REFLOW_TRANSITION:
	WRITECOMMAND(#0x01)
	CLR spkr_disable
	DELAY(#250)
	SETB spkr_disable
	MOV FSM1_state, #STATE_REFLOW
	MOV time+0, #0x00
	MOV time+1, #0x00
	MOV pwm, #30

RAMPUP_L1:
	LJMP MAIN

COOLING_INTERIM:
	LJMP COOLING

REFLOW:
	CJNE A, #STATE_REFLOW, COOLING_INTERIM

	SET_CURSOR(2, 1)
	SEND_CONSTANT_STRING(#str_reflow)
	SET_CURSOR(2, 6)
	SEND_CONSTANT_STRING(#str_target)
	SET_CURSOR(2, 14)
	DISPLAY_BCD(reflow_time)
	DISPLAY_CHAR(#'s')

	CLR C
	MOV A, reflow_time
	SUBB A, #0x60
	JC REFLOW_L1
	; Target reflow time here is equal or more than 60 s.
	MOV R0, A
	MOV A, time+1
	CJNE A, #1, REFLOW_L3
	SJMP REFLOW_L2
REFLOW_L1:
	MOV R0, reflow_time
REFLOW_L2:
	CLR C
	MOV A, time+0
	SUBB A, R0
	JC REFLOW_L3

COOLING_TRANSITION:
	WRITECOMMAND(#0x01)
	CLR spkr_disable
	DELAY(#250)
	SETB spkr_disable
	MOV FSM1_state, #STATE_COOLING
	MOV time+0, #0x00
	MOV time+1, #0x00
	MOV pwm, #0

REFLOW_L3:
	LJMP MAIN

COOLING_L1:
	LJMP MAIN

COOLING:
	; This condition should NEVER be met if the state machine is working.
	CJNE A, #STATE_COOLING, $

	SET_CURSOR(2, 1)
	SEND_CONSTANT_STRING(#str_cooling)

	CLR C
	MOV A, #0x00
	SUBB A, temp_oven+1
	JC COOLING_L1
	MOV A, #0x60
	SUBB A, temp_oven+0
	JC COOLING_L1

RESET_TO_IDLE:
	WRITECOMMAND(#0x01)
	MOV FSM1_state, #STATE_IDLE
	MOV time+0, #0x00
	MOV time+1, #0x00
	MOV pwm, #0
	DELAY(#5)
	SET_CURSOR(1, 1)
	SEND_CONSTANT_STRING(#str_soak_params)
	SET_CURSOR(2, 1)
	SEND_CONSTANT_STRING(#str_reflow_params)
	CLR spkr_disable
	DELAY(#200)
	DELAY(#200)
	SETB spkr_disable
	DELAY(#250)
	CLR spkr_disable
	DELAY(#200)
	DELAY(#200)
	SETB spkr_disable
	DELAY(#250)
	CLR spkr_disable
	DELAY(#250)
	DELAY(#250)
	DELAY(#250)
	SETB spkr_disable
	LJMP MAIN

BACK_TO_IDLE:
	WRITECOMMAND(#0x01)
	MOV FSM1_state, #STATE_IDLE
	MOV time+0, #0x00
	MOV time+1, #0x00
	MOV pwm, #0
	DELAY(#5)
	SET_CURSOR(1, 1)
	SEND_CONSTANT_STRING(#str_soak_params)
	SET_CURSOR(2, 1)
	SEND_CONSTANT_STRING(#str_reflow_params)
	CLR spkr_disable
	DELAY(#200)
	DELAY(#200)
	SETB spkr_disable
	DELAY(#250)
	CLR spkr_disable
	DELAY(#200)
	DELAY(#200)
	SETB spkr_disable
	DELAY(#250)
	CLR spkr_disable
	DELAY(#250)
	DELAY(#250)
	DELAY(#250)
	SETB spkr_disable
	LJMP MAIN

; Initialise APROM flash storage with default reflow profiles.

APROM_INIT:
	PUSH PSW

	; Switch to register bank 1.
	MOV PSW, #0b0000_1000

	MOV R0, #0x40
	MOV R1, #0x70
	MOV R2, #0x20
	MOV R3, #0x50
	MOV R4, #0x50
	MOV R5, #0x60
	MOV R6, #0x25
	MOV R7, #0x45

	; Switch to register bank 2.
	MOV PSW, #0b0001_0000

	MOV R0, #0x60
	MOV R1, #0x55
	MOV R2, #0x30
	MOV R3, #0x40
	MOV R4, #0x55
	MOV R5, #0x65
	MOV R6, #0x30
	MOV R7, #0x55

	LCALL IAP_WRITE

	POP PSW
	RET

; Subroutine code for reading ADC.

READ_ADC:
	PUSH ACC
	CLR ADCF
	SETB ADCS
	JNB ADCF, $

	; Read the ADC result and store in [R1, R0].
	MOV A, ADCRL
	ANL A, #0b0000_1111
	MOV R0, A
	MOV A, ADCRH
	SWAP A
	PUSH ACC
	ANL A, #0b0000_1111
	MOV R1, A
	POP ACC
	ANL A, #0b1111_0000
	ORL A, R0
	MOV R0, A
	POP ACC
	RET

; ADC channel switching subroutines.

SWITCH_TO_AIN0:
	; Select ADC channel 0.
	ANL ADCCON0, #0b1111_0000
	ORL ADCCON0, #0b0000_0000
	RET

SWITCH_TO_AIN1:
	; Select ADC channel 1.
	ANL ADCCON0, #0b1111_0000
	ORL ADCCON0, #0b0000_0001
	RET

SWITCH_TO_AIN4:
	; Select ADC channel 4.
	ANL ADCCON0, #0b1111_0000
	ORL ADCCON0, #0b0000_0100
	RET

SWITCH_TO_AIN7:
	; Select ADC channel 7.
	ANL ADCCON0, #0b1111_0000
	ORL ADCCON0, #0b0000_0111
	RET

; Subroutine for reading ambient and oven temperatures from the ADC.

READ_TEMP:
	; Read the 2.08V LM4040 voltage connected to AIN0 on pin 6.
	LCALL SWITCH_TO_AIN0

	LCALL READ_ADC
	; Save result for later use.
	MOV VAL_LM4040+0, R0
	MOV VAL_LM4040+1, R1

	; LM335.
	LCALL SWITCH_TO_AIN1

	LCALL READ_ADC
	MOV VAL_LM335+0, R0
	MOV VAL_LM335+1, R1

	; Convert to voltage.
	MOV x+0, R0
	MOV x+1, R1
	; Pad other bits with zero.
	MOV x+2, #0
	MOV x+3, #0
	; The MEASURED voltage reference: 4.0959V, with 4 decimal places.
	LOAD_Y(40959)
	LCALL MUL32

	; Retrieve the LM4040 ADC value.
	MOV y+0, VAL_LM4040+0
	MOV y+1, VAL_LM4040+1
	MOV y+2, #0
	MOV y+3, #0
	LCALL DIV32

	; Convert to temperature for LM335.
	LOAD_Y(27300)
	LCALL SUB32
	LOAD_Y(100)
	LCALL MUL32

	; Store LM335 temperature result in z.
	MOV z+0, x+0
	MOV z+1, x+1
	MOV z+2, x+2
	MOV z+3, x+3

	LCALL HEX2BCD
	; Display ambient temperature.
	SET_CURSOR(1, 6)
	DISPLAY_BCD(bcd+2)

	; Read the amplified thermocouple wire signal connected to AIN7.
	LCALL SWITCH_TO_AIN7
	LCALL READ_ADC

	; Convert to voltage.
	MOV x+0, R0
	MOV x+1, R1
	MOV x+2, #0
	MOV x+3, #0
	; The MEASURED voltage reference: 4.0959V, with 4 decimal places.
	LOAD_Y(40959)
	LCALL MUL32

	; Retrieve the LM4040 ADC value.
	MOV y+0, VAL_LM4040+0
	MOV y+1, VAL_LM4040+1
	MOV y+2, #0
	MOV y+3, #0
	LCALL DIV32

	LOAD_Y(670)
	LCALL MUL32
	LOAD_Y(211)
	LCALL DIV32
	LOAD_Y(1000)
	LCALL MUL32
	LOAD_Y(41)
	LCALL DIV32

	; LM335 temperature stored in z.
	MOV y+0, z+0
	MOV y+1, z+1
	MOV y+2, z+2
	MOV y+3, z+3
	LCALL ADD32

	; Convert to BCD and display.
	LCALL HEX2BCD
	SET_CURSOR(1, 1)
	DISPLAY_LOWER_BCD(bcd+3)
	DISPLAY_BCD(bcd+2)

	; Send to PUTTY.
	PUSH ACC
	SEND_BCD(bcd+3)
	SEND_BCD(bcd+2)
	MOV A, #'.'
	LCALL PUTCHAR
	SEND_BCD(bcd+1)
	SEND_BCD(bcd+0)
	MOV A, #'\r'
	LCALL PUTCHAR
	MOV A, #'\n'
	LCALL PUTCHAR
	POP ACC

	MOV temp_oven+0, bcd+2
	MOV temp_oven+1, bcd+3

	RET

; Check push buttons.

CHECK_PUSH_BUTTON MAC PB, HEX
	CLR C
	MOV A, ADCRH
	SUBB A, %1
	JC $+7
	CLR %0
	POP ACC
	RET
ENDMAC

ADC_TO_PB:
	LCALL SWITCH_TO_AIN4

	; Wait for ADC to finish A/D conversion.
	CLR ADCF
	SETB ADCS
	JNB ADCF, $

	; Initialise buttons.
	SETB OVEN_BUTTON
	SETB S_BUTTON
	MOV PB, #0xFF

	; The accumulator is popped either in the macro expansion
	; or at the very end of this subroutine.
	PUSH ACC
	CHECK_PUSH_BUTTON(PB.7, #0xF0)
	CHECK_PUSH_BUTTON(PB.6, #0xD0)
	CHECK_PUSH_BUTTON(PB.5, #0xB0)
	CHECK_PUSH_BUTTON(PB.4, #0x90)
	CHECK_PUSH_BUTTON(PB.3, #0x70)
	CHECK_PUSH_BUTTON(PB.2, #0x50)
	CHECK_PUSH_BUTTON(PB.1, #0x30)
	CHECK_PUSH_BUTTON(PB.0, #0x10)
	POP ACC
	RET

; Push button handling.

CHANGE_VALUE MAC VALUE, PB, ROW, COL
CHANGE_%0:
	PUSH ACC
	DELAY(#125)
	JB %1, $+18
	JB %1, $

	MOV A, %0
	JNB S_BUTTON, $+7
	ADD A, #1
	SJMP $+4
	ADD A, #0x99
	DA A
	MOV %0, A

	; Update LCD Display at specified ROW and COL.
	LCALL CLEAR_ARROWS
	SET_CURSOR(%2, %3)
	WRITEDATA(#0x00)

	POP ACC
	RET
ENDMAC

CHANGE_VALUE(REFLOW_TIME, PB.4, 2, 13)
CHANGE_VALUE(REFLOW_TEMP, PB.5, 2, 8)
CHANGE_VALUE(SOAK_TIME, PB.6, 1, 13)
CHANGE_VALUE(SOAK_TEMP, PB.7, 1, 8)

CLEAR_ARROWS:
	SET_CURSOR(1, 8)
	DISPLAY_CHAR(#' ')
	SET_CURSOR(1, 13)
	DISPLAY_CHAR(#' ')
	SET_CURSOR(2, 8)
	DISPLAY_CHAR(#' ')
	SET_CURSOR(2, 13)
	DISPLAY_CHAR(#' ')
	RET

LOAD_PRESET MAC PRESET, PB
LOAD_PRESET_%0:
	PUSH ACC
	DELAY(#125)
	JB %1, ?NEXT_%0
	LCALL FETCH_PRESET_%0
?NEXT_%0:
	POP ACC
	RET
ENDMAC

LOAD_PRESET(1, PB.3)
LOAD_PRESET(2, PB.2)
LOAD_PRESET(3, PB.1)
LOAD_PRESET(4, PB.0)

FETCH_PRESET MAC PRESET, ADDR, REGBANK
FETCH_PRESET_%0:
	PUSH ACC
	PUSH PSW

	MOV DPTR, %1

	ANL PSW, #0b1110_0111
	ORL PSW, #(%2 << 3)

	MOV A, #0x00
	MOVC A, @A+DPTR
	MOV soak_temp, A

	MOV A, #0x01
	MOVC A, @A+DPTR
	MOV soak_time, A

	MOV A, #0x02
	MOVC A, @A+DPTR
	MOV reflow_temp, A

	MOV A, #0x03
	MOVC A, @A+DPTR
	MOV reflow_time, A

	POP PSW
	POP ACC
	RET
ENDMAC

FETCH_PRESET(1, #0x400, 0b01)
FETCH_PRESET(2, #0x404, 0b01)
FETCH_PRESET(3, #0x408, 0b10)
FETCH_PRESET(4, #0x40C, 0b10)

SAVE_PRESET MAC PRESET, PB, REGBANK, RA, RB, RC, RD
SAVE_PRESET_%0:
	PUSH ACC
	PUSH PSW
	DELAY(#125)
	JB %1, ?SAVE_PRESET_%0
	LCALL IAP_READ

	ANL PSW, #0b1110_0111
	ORL PSW, #(%2 << 3)

	MOV %3, soak_temp
	MOV %4, soak_time
	MOV %5, reflow_temp
	MOV %6, reflow_time

	LCALL IAP_WRITE
?SAVE_PRESET_%0:
	POP PSW
	POP ACC
	RET
ENDMAC

SAVE_PRESET(1, PB.3, 0b01, R0, R1, R2, R3)
SAVE_PRESET(2, PB.2, 0b01, R4, R5, R6, R7)
SAVE_PRESET(3, PB.1, 0b10, R0, R1, R2, R3)
SAVE_PRESET(4, PB.0, 0b10, R4, R5, R6, R7)
