/*
 * Z80 CPU Emulator Core
 * Adapted from RunCPM (https://github.com/MockbaTheBorg/RunCPM) cpu1.h
 * Copyright (c) 2017 Mockba the Borg (MIT License)
 * Adapted for standalone, deterministic, 16-bit bounds-safe step execution in moria8 cpm_runner.
 */

#include "z80.h"
#include "bdos.h"

#include <stdio.h>

typedef int8_t int8;
typedef int16_t int16;
typedef int32_t int32;
typedef uint8_t uint8;
typedef uint16_t uint16;
typedef uint32_t uint32;

#define ADDRMASK 0xffff
#define LOW_DIGIT(x) ((x) & 0xf)
#define HIGH_DIGIT(x) (((x) >> 4) & 0xf)
#define LOW_REGISTER(x) ((x) & 0xff)
#define HIGH_REGISTER(x) (((x) >> 8) & 0xff)
#define SET_LOW_REGISTER(x, v) (x) = (((x) & 0xff00U) | ((uint32)(v) & 0xffU))
#define SET_HIGH_REGISTER(x, v) (x) = (((x) & 0xffU) | (((uint32)(v) & 0xffU) << 8))

#define FLAG_C 1
#define FLAG_N 2
#define FLAG_P 4
#define FLAG_H 16
#define FLAG_Z 64
#define FLAG_S 128

#define SETFLAG(f, c) (AF = (c) ? (AF | FLAG_ ## f) : (AF & ~FLAG_ ## f))
#define TSTFLAG(f) ((AF & FLAG_ ## f) != 0)

#define SET_PVS(s) (((cbits >> 6) ^ (cbits >> 5)) & 4)
#define SET_PV (SET_PVS(sum))
#define SET_PV2(x) ((temp == (x)) << 2)

#define INCR(val) IR = (IR & ~0x7fU) | ((IR + (uint32)(val)) & 0x7fU)

static inline uint8 z80_get_byte(const CpmVm *vm, uint16 a) {
    return vm->ram[a];
}

static inline void z80_put_byte(CpmVm *vm, uint16 a, uint8 v) {
    vm->ram[a] = v;
}

static inline uint16 z80_get_word(const CpmVm *vm, uint16 a) {
    return (uint16)(vm->ram[a] | (vm->ram[(uint16)(a + 1)] << 8));
}

static inline void z80_put_word(CpmVm *vm, uint16 a, uint32 v) {
    vm->ram[a] = (uint8)(v & 0xffU);
    vm->ram[(uint16)(a + 1)] = (uint8)((v >> 8) & 0xffU);
}

#define GET_BYTE(a) z80_get_byte(vm, (uint16)(a))
#define PUT_BYTE(a, v) z80_put_byte(vm, (uint16)(a), (uint8)(v))
#define GET_WORD(a) z80_get_word(vm, (uint16)(a))
#define PUT_WORD(a, v) z80_put_word(vm, (uint16)(a), (uint32)(v))

#define RAM_MM(a) GET_BYTE(a--)
#define RAM_PP(a) GET_BYTE(a++)
#define PUT_BYTE_PP(a, v) PUT_BYTE(a++, v)
#define PUT_BYTE_MM(a, v) PUT_BYTE(a--, v)
#define MM_PUT_BYTE(a, v) PUT_BYTE(--a, v)

#define PUSH(x) do { uint32 _pv = (uint32)(x); MM_PUT_BYTE(SP, _pv >> 8); MM_PUT_BYTE(SP, _pv); } while (0)
#define POP(x) do { uint32 _lo = RAM_PP(SP); (x) = _lo + (RAM_PP(SP) << 8); } while (0)

#define JPC(cond) do { if (cond) { PC = GET_WORD(PC); } else { PC = (PC + 2) & 0xffffU; } } while (0)
#define CALLC(cond) do { if (cond) { uint32 _ca = GET_WORD(PC); PUSH(PC + 2); PC = _ca; } else { PC = (PC + 2) & 0xffffU; } } while (0)

#define INOUTFLAGS(syxz, x) AF = (AF & 0xff00U) | (syxz) | ((acu & 0x80U) >> 6) | ((acu + (x)) > 0xffU ? (FLAG_C | FLAG_H) : 0U) | parityTable[((acu + (x)) & 7U) ^ temp]
#define INOUTFLAGS_ZERO(x) INOUTFLAGS(FLAG_Z, x)
#define INOUTFLAGS_NONZERO(x) INOUTFLAGS((HIGH_REGISTER(BC) & 0xa8U) | ((HIGH_REGISTER(BC) == 0) << 6), x)

static void cpu_out(uint32 p, uint32 v) {
    (void)p;
    (void)v;
}

static uint32 cpu_in(uint32 p) {
    (void)p;
    return 0;
}

static bool tables_initialized = false;

static uint8 parityTable[256];
static uint8 incTable[257];
static uint8 decTable[256];
static uint8 cbitsTable[512];
static uint16 cbitsDup8Table[512];
static uint8 cbitsDup16Table[512];
static uint8 cbits2Table[512];
static uint16 rrcaTable[256];
static uint16 rraTable[256];
static uint16 addTable[512];
static uint16 subTable[256];
static uint16 andTable[256];
static uint16 xororTable[256];
static uint8 rotateShiftTable[256];
static uint8 incZ80Table[257];
static uint8 decZ80Table[256];
static uint8 cbitsZ80Table[512];
static uint8 cbitsZ80DupTable[512];
static uint8 cbits2Z80Table[512];
static uint8 cbits2Z80DupTable[512];
static uint8 negTable[256];
static uint16 rrdrldTable[256];
static uint8 cpTable[256];

void z80_init_tables(void) {
    if (tables_initialized) return;
    tables_initialized = true;
	// 256 bytes tables
	for (int i = 0; i < 256; i++) {
		char c = 0;
		for (int j = 0; j < 8; j++) {
			if (i & (1 << j))
				c++;
		}
		parityTable[i] = (c & 1) ? 0 : 4;
		decTable[i] = (i & 0xa8) | (((i & 0xff) == 0) << 6) | (((i & 0xf) == 0xf) << 4) | 2;
		rrcaTable[i] = ((i & 1) << 15) | ((i >> 1) << 8) | ((i >> 1) & 0x28) | (i & 1);
		rraTable[i] = ((i >> 1) << 8) | ((i >> 1) & 0x28) | (i & 1);
		subTable[i] = ((i & 0xff) << 8) | (i & 0xa8) | (((i & 0xff) == 0) << 6) | 2;
		andTable[i] = (i << 8) | (i & 0xa8) | ((i == 0) << 6) | 0x10 | parityTable[i];
		xororTable[i] = (i << 8) | (i & 0xa8) | ((i == 0) << 6) | parityTable[i];
		rotateShiftTable[i] = (i & 0xa8) | (((i & 0xff) == 0) << 6) | parityTable[i & 0xff];
		decZ80Table[i] = (i & 0xa8) | (((i & 0xff) == 0) << 6) | (((i & 0xf) == 0xf) << 4) | ((i == 0x7f) << 2) | 2;
		negTable[i] = (((i & 0x0f) != 0) << 4) | ((i == 0x80) << 2) | 2 | (i != 0);
		rrdrldTable[i] = (i << 8) | (i & 0xa8) | (((i & 0xff) == 0) << 6) | parityTable[i];
		cpTable[i] = (i & 0x80) | (((i & 0xff) == 0) << 6);
	}
	// 257 bytes tables
	for (int i = 0; i < 257; i++) {
		incTable[i] = (i & 0xa8) | (((i & 0xff) == 0) << 6) | (((i & 0xf) == 0) << 4);
		incZ80Table[i] = (i & 0xa8) | (((i & 0xff) == 0) << 6) | (((i & 0xf) == 0) << 4) | ((i == 0x80) << 2);
	}
	// 512 bytes tables
	for (int i = 0; i < 512; i++) {
		cbitsTable[i] = (i & 0x10) | ((i >> 8) & 1);
		cbitsDup8Table[i] = (i & 0x10) | ((i >> 8) & 1) | ((i & 0xff) << 8) | (i & 0xa8) | (((i & 0xff) == 0) << 6);
		cbitsDup16Table[i] = (i & 0x10) | ((i >> 8) & 1) | (i & 0x28);
		cbits2Table[i] = (i & 0x10) | ((i >> 8) & 1) | 2;
		addTable[i] = ((i & 0xff) << 8) | (i & 0xa8) | (((i & 0xff) == 0) << 6);
		cbitsZ80Table[i] = (i & 0x10) | (((i >> 6) ^ (i >> 5)) & 4) | ((i >> 8) & 1);
		cbitsZ80DupTable[i] = (i & 0x10) | (((i >> 6) ^ (i >> 5)) & 4) | ((i >> 8) & 1) | (i & 0xa8);
		cbits2Z80Table[i] = (i & 0x10) | (((i >> 6) ^ (i >> 5)) & 4) | ((i >> 8) & 1) | 2;
		cbits2Z80DupTable[i] = (i & 0x10) | (((i >> 6) ^ (i >> 5)) & 4) | ((i >> 8) & 1) | 2 | (i & 0xa8);
	}
}

static uint64_t z80_exec_one(CpmVm *vm) {
    uint32 AF = vm->af;
    uint32 BC = vm->bc;
    uint32 DE = vm->de;
    uint32 HL = vm->hl;
    uint32 IX = vm->ix;
    uint32 IY = vm->iy;
    uint32 PC = vm->pc;
    uint32 SP = vm->sp;
    uint32 AF1 = vm->af1;
    uint32 BC1 = vm->bc1;
    uint32 DE1 = vm->de1;
    uint32 HL1 = vm->hl1;
    uint32 IFF = vm->iff;
    uint32 IR = vm->ir;

    uint32 temp = 0;
    uint32 acu = 0;
    uint32 sum = 0;
    uint32 cbits = 0;
    uint32 op = 0;
    uint32 adr = 0;
    uint64_t steps = 1;

    if (PC == vm->bdos_entry) {
        if (bdos_call(vm)) {
            SP = vm->sp;
            POP(PC);
            INCR(7);
            vm->ir = IR & 0xffffU;
            vm->pc = PC & 0xffffU;
            vm->sp = SP & 0xffffU;
        }
        vm->total_steps++;
        return 1;
    }

    if (PC >= vm->bios_base) {
        uint32 max_bios = (vm->bios_base == 0xFF00U) ? 33U : 17U;
        uint32 off = PC - vm->bios_base;
        if (off < max_bios * 3U && (off % 3U) == 0U) {
            if (bios_call(vm, (uint8_t)(off / 3U))) {
                SP = vm->sp;
                POP(PC);
                INCR(3);
                vm->ir = IR & 0xffffU;
                vm->pc = PC & 0xffffU;
                vm->sp = SP & 0xffffU;
            }
            vm->total_steps++;
            return 1;
        }
    }

    INCR(1);
		switch (RAM_PP(PC)) {

		case 0x00:      /* NOP */
			break;

		case 0x01:      /* LD BC,nnnn */
			BC = GET_WORD(PC++);
			++PC;
			break;

		case 0x02:      /* LD (BC),A */
			PUT_BYTE(BC, HIGH_REGISTER(AF));
			break;

		case 0x03:      /* INC BC */
			++BC;
			break;

		case 0x04:      /* INC B */
			BC += 0x100;
			temp = HIGH_REGISTER(BC);
			AF = (AF & ~0xfe) | incTable[temp] | SET_PV2(0x80); /* SET_PV2 uses temp */
			break;

		case 0x05:      /* DEC B */
			BC -= 0x100;
			temp = HIGH_REGISTER(BC);
			AF = (AF & ~0xfe) | decTable[temp] | SET_PV2(0x7f); /* SET_PV2 uses temp */
			break;

		case 0x06:      /* LD B,nn */
			SET_HIGH_REGISTER(BC, RAM_PP(PC));
			break;

		case 0x07:      /* RLCA */
			AF = ((AF >> 7) & 0x0128) | ((AF << 1) & ~0x1ff) |
				(AF & 0xc4) | ((AF >> 15) & 1);
			break;

		case 0x08:      /* EX AF,AF' */
		    AF ^= AF1;
    		AF1 ^= AF;
    		AF ^= AF1;
			break;

		case 0x09:      /* ADD HL,BC */
			HL &= ADDRMASK;
			BC &= ADDRMASK;
			sum = HL + BC;
			AF = (AF & ~0x3b) | ((sum >> 8) & 0x28) | cbitsTable[(HL ^ BC ^ sum) >> 8];
			HL = sum;
			break;

		case 0x0a:      /* LD A,(BC) */
			SET_HIGH_REGISTER(AF, GET_BYTE(BC));
			break;

		case 0x0b:      /* DEC BC */
			--BC;
			break;

		case 0x0c:      /* INC C */
			temp = LOW_REGISTER(BC) + 1;
			SET_LOW_REGISTER(BC, temp);
			AF = (AF & ~0xfe) | incTable[temp] | SET_PV2(0x80);
			break;

		case 0x0d:      /* DEC C */
			temp = LOW_REGISTER(BC) - 1;
			SET_LOW_REGISTER(BC, temp);
			AF = (AF & ~0xfe) | decTable[temp & 0xff] | SET_PV2(0x7f);
			break;

		case 0x0e:      /* LD C,nn */
			SET_LOW_REGISTER(BC, RAM_PP(PC));
			break;

		case 0x0f:      /* RRCA */
			AF = (AF & 0xc4) | rrcaTable[HIGH_REGISTER(AF)];
			break;

		case 0x10:      /* DJNZ dd */
			if ((BC -= 0x100) & 0xff00)
				PC += (int8)GET_BYTE(PC) + 1;
			else
				++PC;
			break;

		case 0x11:      /* LD DE,nnnn */
			DE = GET_WORD(PC++);
			++PC;
			break;

		case 0x12:      /* LD (DE),A */
			PUT_BYTE(DE, HIGH_REGISTER(AF));
			break;

		case 0x13:      /* INC DE */
			++DE;
			break;

		case 0x14:      /* INC D */
			DE += 0x100;
			temp = HIGH_REGISTER(DE);
			AF = (AF & ~0xfe) | incTable[temp] | SET_PV2(0x80); /* SET_PV2 uses temp */
			break;

		case 0x15:      /* DEC D */
			DE -= 0x100;
			temp = HIGH_REGISTER(DE);
			AF = (AF & ~0xfe) | decTable[temp] | SET_PV2(0x7f); /* SET_PV2 uses temp */
			break;

		case 0x16:      /* LD D,nn */
			SET_HIGH_REGISTER(DE, RAM_PP(PC));
			break;

		case 0x17:      /* RLA */
			AF = ((AF << 8) & 0x0100) | ((AF >> 7) & 0x28) | ((AF << 1) & ~0x01ff) |
				(AF & 0xc4) | ((AF >> 15) & 1);
			break;

		case 0x18:      /* JR dd */
			PC += (int8)GET_BYTE(PC) + 1;
			break;

		case 0x19:      /* ADD HL,DE */
			HL &= ADDRMASK;
			DE &= ADDRMASK;
			sum = HL + DE;
			AF = (AF & ~0x3b) | ((sum >> 8) & 0x28) | cbitsTable[(HL ^ DE ^ sum) >> 8];
			HL = sum;
			break;

		case 0x1a:      /* LD A,(DE) */
			SET_HIGH_REGISTER(AF, GET_BYTE(DE));
			break;

		case 0x1b:      /* DEC DE */
			--DE;
			break;

		case 0x1c:      /* INC E */
			temp = LOW_REGISTER(DE) + 1;
			SET_LOW_REGISTER(DE, temp);
			AF = (AF & ~0xfe) | incTable[temp] | SET_PV2(0x80);
			break;

		case 0x1d:      /* DEC E */
			temp = LOW_REGISTER(DE) - 1;
			SET_LOW_REGISTER(DE, temp);
			AF = (AF & ~0xfe) | decTable[temp & 0xff] | SET_PV2(0x7f);
			break;

		case 0x1e:      /* LD E,nn */
			SET_LOW_REGISTER(DE, RAM_PP(PC));
			break;

		case 0x1f:      /* RRA */
			AF = ((AF & 1) << 15) | (AF & 0xc4) | rraTable[HIGH_REGISTER(AF)];
			break;

		case 0x20:      /* JR NZ,dd */
			if (TSTFLAG(Z))
				++PC;
			else
				PC += (int8)GET_BYTE(PC) + 1;
			break;

		case 0x21:      /* LD HL,nnnn */
			HL = GET_WORD(PC++);
			++PC;
			break;

		case 0x22:      /* LD (nnnn),HL */
			PUT_WORD(GET_WORD(PC++), HL);
			++PC;
			break;

		case 0x23:      /* INC HL */
			++HL;
			break;

		case 0x24:      /* INC H */
			HL += 0x100;
			temp = HIGH_REGISTER(HL);
			AF = (AF & ~0xfe) | incTable[temp] | SET_PV2(0x80); /* SET_PV2 uses temp */
			break;

		case 0x25:      /* DEC H */
			HL -= 0x100;
			temp = HIGH_REGISTER(HL);
			AF = (AF & ~0xfe) | decTable[temp] | SET_PV2(0x7f); /* SET_PV2 uses temp */
			break;

		case 0x26:      /* LD H,nn */
			SET_HIGH_REGISTER(HL, RAM_PP(PC));
			break;

		case 0x27:      /* DAA */
			acu = HIGH_REGISTER(AF);
			temp = LOW_DIGIT(acu);
			cbits = TSTFLAG(C);
			if (TSTFLAG(N)) {   /* last operation was a subtract */
				int hd = cbits || acu > 0x99;
				if (TSTFLAG(H) || (temp > 9)) { /* adjust low digit */
					if (temp > 5)
						SETFLAG(H, 0);
					acu -= 6;
					acu &= 0xff;
				}
				if (hd)
					acu -= 0x160;   /* adjust high digit */
			} else {          /* last operation was an add */
				if (TSTFLAG(H) || (temp > 9)) { /* adjust low digit */
					SETFLAG(H, (temp > 9));
					acu += 6;
				}
				if (cbits || ((acu & 0x1f0) > 0x90))
					acu += 0x60;   /* adjust high digit */
			}
			AF = (AF & 0x12) | rrdrldTable[acu & 0xff] | ((acu >> 8) & 1) | cbits;
			break;

		case 0x28:      /* JR Z,dd */
			if (TSTFLAG(Z))
				PC += (int8)GET_BYTE(PC) + 1;
			else
				++PC;
			break;

		case 0x29:      /* ADD HL,HL */
			HL &= ADDRMASK;
			sum = HL + HL;
			AF = (AF & ~0x3b) | cbitsDup16Table[sum >> 8];
			HL = sum;
			break;

		case 0x2a:      /* LD HL,(nnnn) */
			HL = GET_WORD(GET_WORD(PC++));
			++PC;
			break;

		case 0x2b:      /* DEC HL */
			--HL;
			break;

		case 0x2c:      /* INC L */
			temp = LOW_REGISTER(HL) + 1;
			SET_LOW_REGISTER(HL, temp);
			AF = (AF & ~0xfe) | incTable[temp] | SET_PV2(0x80);
			break;

		case 0x2d:      /* DEC L */
			temp = LOW_REGISTER(HL) - 1;
			SET_LOW_REGISTER(HL, temp);
			AF = (AF & ~0xfe) | decTable[temp & 0xff] | SET_PV2(0x7f);
			break;

		case 0x2e:      /* LD L,nn */
			SET_LOW_REGISTER(HL, RAM_PP(PC));
			break;

		case 0x2f:      /* CPL */
			AF = (~AF & ~0xff) | (AF & 0xc5) | ((~AF >> 8) & 0x28) | 0x12;
			break;

		case 0x30:      /* JR NC,dd */
			if (TSTFLAG(C))
				++PC;
			else
				PC += (int8)GET_BYTE(PC) + 1;
			break;

		case 0x31:      /* LD SP,nnnn */
			SP = GET_WORD(PC++);
			++PC;
			break;

		case 0x32:      /* LD (nnnn),A */
			PUT_BYTE(GET_WORD(PC++), HIGH_REGISTER(AF));
			++PC;
			break;

		case 0x33:      /* INC SP */
			++SP;
			break;

		case 0x34:      /* INC (HL) */
			temp = GET_BYTE(HL) + 1;
			PUT_BYTE(HL, temp);
			AF = (AF & ~0xfe) | incTable[temp] | SET_PV2(0x80);
			break;

		case 0x35:      /* DEC (HL) */
			temp = GET_BYTE(HL) - 1;
			PUT_BYTE(HL, temp);
			AF = (AF & ~0xfe) | decTable[temp & 0xff] | SET_PV2(0x7f);
			break;

		case 0x36:      /* LD (HL),nn */
			PUT_BYTE(HL, RAM_PP(PC));
			break;

		case 0x37:      /* SCF */
			AF = (AF & ~0x3b) | ((AF >> 8) & 0x28) | 1;
			break;

		case 0x38:      /* JR C,dd */
			if (TSTFLAG(C))
				PC += (int8)GET_BYTE(PC) + 1;
			else
				++PC;
			break;

		case 0x39:      /* ADD HL,SP */
			HL &= ADDRMASK;
			SP &= ADDRMASK;
			sum = HL + SP;
			AF = (AF & ~0x3b) | ((sum >> 8) & 0x28) | cbitsTable[(HL ^ SP ^ sum) >> 8];
			HL = sum;
			break;

		case 0x3a:      /* LD A,(nnnn) */
			SET_HIGH_REGISTER(AF, GET_BYTE(GET_WORD(PC++)));
			++PC;
			break;

		case 0x3b:      /* DEC SP */
			--SP;
			break;

		case 0x3c:      /* INC A */
			AF += 0x100;
			temp = HIGH_REGISTER(AF);
			AF = (AF & ~0xfe) | incTable[temp] | SET_PV2(0x80); /* SET_PV2 uses temp */
			break;

		case 0x3d:      /* DEC A */
			AF -= 0x100;
			temp = HIGH_REGISTER(AF);
			AF = (AF & ~0xfe) | decTable[temp] | SET_PV2(0x7f); /* SET_PV2 uses temp */
			break;

		case 0x3e:      /* LD A,nn */
			SET_HIGH_REGISTER(AF, RAM_PP(PC));
			break;

		case 0x3f:      /* CCF */
			AF = (AF & ~0x3b) | ((AF >> 8) & 0x28) | ((AF & 1) << 4) | (~AF & 1);
			break;

		case 0x40:      /* LD B,B */
			break;

		case 0x41:      /* LD B,C */
			BC = (BC & 0xff) | ((BC & 0xff) << 8);
			break;

		case 0x42:      /* LD B,D */
			BC = (BC & 0xff) | (DE & ~0xff);
			break;

		case 0x43:      /* LD B,E */
			BC = (BC & 0xff) | ((DE & 0xff) << 8);
			break;

		case 0x44:      /* LD B,H */
			BC = (BC & 0xff) | (HL & ~0xff);
			break;

		case 0x45:      /* LD B,L */
			BC = (BC & 0xff) | ((HL & 0xff) << 8);
			break;

		case 0x46:      /* LD B,(HL) */
			SET_HIGH_REGISTER(BC, GET_BYTE(HL));
			break;

		case 0x47:      /* LD B,A */
			BC = (BC & 0xff) | (AF & ~0xff);
			break;

		case 0x48:      /* LD C,B */
			BC = (BC & ~0xff) | ((BC >> 8) & 0xff);
			break;

		case 0x49:      /* LD C,C */
			break;

		case 0x4a:      /* LD C,D */
			BC = (BC & ~0xff) | ((DE >> 8) & 0xff);
			break;

		case 0x4b:      /* LD C,E */
			BC = (BC & ~0xff) | (DE & 0xff);
			break;

		case 0x4c:      /* LD C,H */
			BC = (BC & ~0xff) | ((HL >> 8) & 0xff);
			break;

		case 0x4d:      /* LD C,L */
			BC = (BC & ~0xff) | (HL & 0xff);
			break;

		case 0x4e:      /* LD C,(HL) */
			SET_LOW_REGISTER(BC, GET_BYTE(HL));
			break;

		case 0x4f:      /* LD C,A */
			BC = (BC & ~0xff) | ((AF >> 8) & 0xff);
			break;

		case 0x50:      /* LD D,B */
			DE = (DE & 0xff) | (BC & ~0xff);
			break;

		case 0x51:      /* LD D,C */
			DE = (DE & 0xff) | ((BC & 0xff) << 8);
			break;

		case 0x52:      /* LD D,D */
			break;

		case 0x53:      /* LD D,E */
			DE = (DE & 0xff) | ((DE & 0xff) << 8);
			break;

		case 0x54:      /* LD D,H */
			DE = (DE & 0xff) | (HL & ~0xff);
			break;

		case 0x55:      /* LD D,L */
			DE = (DE & 0xff) | ((HL & 0xff) << 8);
			break;

		case 0x56:      /* LD D,(HL) */
			SET_HIGH_REGISTER(DE, GET_BYTE(HL));
			break;

		case 0x57:      /* LD D,A */
			DE = (DE & 0xff) | (AF & ~0xff);
			break;

		case 0x58:      /* LD E,B */
			DE = (DE & ~0xff) | ((BC >> 8) & 0xff);
			break;

		case 0x59:      /* LD E,C */
			DE = (DE & ~0xff) | (BC & 0xff);
			break;

		case 0x5a:      /* LD E,D */
			DE = (DE & ~0xff) | ((DE >> 8) & 0xff);
			break;

		case 0x5b:      /* LD E,E */
			break;

		case 0x5c:      /* LD E,H */
			DE = (DE & ~0xff) | ((HL >> 8) & 0xff);
			break;

		case 0x5d:      /* LD E,L */
			DE = (DE & ~0xff) | (HL & 0xff);
			break;

		case 0x5e:      /* LD E,(HL) */
			SET_LOW_REGISTER(DE, GET_BYTE(HL));
			break;

		case 0x5f:      /* LD E,A */
			DE = (DE & ~0xff) | ((AF >> 8) & 0xff);
			break;

		case 0x60:      /* LD H,B */
			HL = (HL & 0xff) | (BC & ~0xff);
			break;

		case 0x61:      /* LD H,C */
			HL = (HL & 0xff) | ((BC & 0xff) << 8);
			break;

		case 0x62:      /* LD H,D */
			HL = (HL & 0xff) | (DE & ~0xff);
			break;

		case 0x63:      /* LD H,E */
			HL = (HL & 0xff) | ((DE & 0xff) << 8);
			break;

		case 0x64:      /* LD H,H */
			break;

		case 0x65:      /* LD H,L */
			HL = (HL & 0xff) | ((HL & 0xff) << 8);
			break;

		case 0x66:      /* LD H,(HL) */
			SET_HIGH_REGISTER(HL, GET_BYTE(HL));
			break;

		case 0x67:      /* LD H,A */
			HL = (HL & 0xff) | (AF & ~0xff);
			break;

		case 0x68:      /* LD L,B */
			HL = (HL & ~0xff) | ((BC >> 8) & 0xff);
			break;

		case 0x69:      /* LD L,C */
			HL = (HL & ~0xff) | (BC & 0xff);
			break;

		case 0x6a:      /* LD L,D */
			HL = (HL & ~0xff) | ((DE >> 8) & 0xff);
			break;

		case 0x6b:      /* LD L,E */
			HL = (HL & ~0xff) | (DE & 0xff);
			break;

		case 0x6c:      /* LD L,H */
			HL = (HL & ~0xff) | ((HL >> 8) & 0xff);
			break;

		case 0x6d:      /* LD L,L */
			break;

		case 0x6e:      /* LD L,(HL) */
			SET_LOW_REGISTER(HL, GET_BYTE(HL));
			break;

		case 0x6f:      /* LD L,A */
			HL = (HL & ~0xff) | ((AF >> 8) & 0xff);
			break;

		case 0x70:      /* LD (HL),B */
			PUT_BYTE(HL, HIGH_REGISTER(BC));
			break;

		case 0x71:      /* LD (HL),C */
			PUT_BYTE(HL, LOW_REGISTER(BC));
			break;

		case 0x72:      /* LD (HL),D */
			PUT_BYTE(HL, HIGH_REGISTER(DE));
			break;

		case 0x73:      /* LD (HL),E */
			PUT_BYTE(HL, LOW_REGISTER(DE));
			break;

		case 0x74:      /* LD (HL),H */
			PUT_BYTE(HL, HIGH_REGISTER(HL));
			break;

		case 0x75:      /* LD (HL),L */
			PUT_BYTE(HL, LOW_REGISTER(HL));
			break;

		case 0x76:      /* HALT */
			PC = (PC - 1) & 0xffff;
			vm->status = CPM_HALTED;
			vm->exit_code = 1;
			snprintf(vm->exit_reason, sizeof(vm->exit_reason), "halt");
			break;

		case 0x77:      /* LD (HL),A */
			PUT_BYTE(HL, HIGH_REGISTER(AF));
			break;

		case 0x78:      /* LD A,B */
			AF = (AF & 0xff) | (BC & ~0xff);
			break;

		case 0x79:      /* LD A,C */
			AF = (AF & 0xff) | ((BC & 0xff) << 8);
			break;

		case 0x7a:      /* LD A,D */
			AF = (AF & 0xff) | (DE & ~0xff);
			break;

		case 0x7b:      /* LD A,E */
			AF = (AF & 0xff) | ((DE & 0xff) << 8);
			break;

		case 0x7c:      /* LD A,H */
			AF = (AF & 0xff) | (HL & ~0xff);
			break;

		case 0x7d:      /* LD A,L */
			AF = (AF & 0xff) | ((HL & 0xff) << 8);
			break;

		case 0x7e:      /* LD A,(HL) */
			SET_HIGH_REGISTER(AF, GET_BYTE(HL));
			break;

		case 0x7f:      /* LD A,A */
			break;

		case 0x80:      /* ADD A,B */
			temp = HIGH_REGISTER(BC);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp;
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0x81:      /* ADD A,C */
			temp = LOW_REGISTER(BC);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp;
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0x82:      /* ADD A,D */
			temp = HIGH_REGISTER(DE);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp;
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0x83:      /* ADD A,E */
			temp = LOW_REGISTER(DE);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp;
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0x84:      /* ADD A,H */
			temp = HIGH_REGISTER(HL);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp;
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0x85:      /* ADD A,L */
			temp = LOW_REGISTER(HL);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp;
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0x86:      /* ADD A,(HL) */
			temp = GET_BYTE(HL);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp;
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0x87:      /* ADD A,A */
			cbits = 2 * HIGH_REGISTER(AF);
			AF = cbitsDup8Table[cbits] | (SET_PVS(cbits));
			break;

		case 0x88:      /* ADC A,B */
			temp = HIGH_REGISTER(BC);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp + TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0x89:      /* ADC A,C */
			temp = LOW_REGISTER(BC);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp + TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0x8a:      /* ADC A,D */
			temp = HIGH_REGISTER(DE);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp + TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0x8b:      /* ADC A,E */
			temp = LOW_REGISTER(DE);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp + TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0x8c:      /* ADC A,H */
			temp = HIGH_REGISTER(HL);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp + TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0x8d:      /* ADC A,L */
			temp = LOW_REGISTER(HL);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp + TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0x8e:      /* ADC A,(HL) */
			temp = GET_BYTE(HL);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp + TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0x8f:      /* ADC A,A */
			cbits = 2 * HIGH_REGISTER(AF) + TSTFLAG(C);
			AF = cbitsDup8Table[cbits] | (SET_PVS(cbits));
			break;

		case 0x90:      /* SUB B */
			temp = HIGH_REGISTER(BC);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0x91:      /* SUB C */
			temp = LOW_REGISTER(BC);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0x92:      /* SUB D */
			temp = HIGH_REGISTER(DE);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0x93:      /* SUB E */
			temp = LOW_REGISTER(DE);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0x94:      /* SUB H */
			temp = HIGH_REGISTER(HL);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0x95:      /* SUB L */
			temp = LOW_REGISTER(HL);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0x96:      /* SUB (HL) */
			temp = GET_BYTE(HL);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0x97:      /* SUB A */
			AF = 0x42;
			break;

		case 0x98:      /* SBC A,B */
			temp = HIGH_REGISTER(BC);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp - TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0x99:      /* SBC A,C */
			temp = LOW_REGISTER(BC);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp - TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0x9a:      /* SBC A,D */
			temp = HIGH_REGISTER(DE);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp - TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0x9b:      /* SBC A,E */
			temp = LOW_REGISTER(DE);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp - TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0x9c:      /* SBC A,H */
			temp = HIGH_REGISTER(HL);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp - TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0x9d:      /* SBC A,L */
			temp = LOW_REGISTER(HL);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp - TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0x9e:      /* SBC A,(HL) */
			temp = GET_BYTE(HL);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp - TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0x9f:      /* SBC A,A */
			cbits = -TSTFLAG(C);
			AF = subTable[cbits & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PVS(cbits));
			break;

		case 0xa0:      /* AND B */
			AF = andTable[((AF & BC) >> 8) & 0xff];
			break;

		case 0xa1:      /* AND C */
			AF = andTable[((AF >> 8)& BC) & 0xff];
			break;

		case 0xa2:      /* AND D */
			AF = andTable[((AF & DE) >> 8) & 0xff];
			break;

		case 0xa3:      /* AND E */
			AF = andTable[((AF >> 8)& DE) & 0xff];
			break;

		case 0xa4:      /* AND H */
			AF = andTable[((AF & HL) >> 8) & 0xff];
			break;

		case 0xa5:      /* AND L */
			AF = andTable[((AF >> 8)& HL) & 0xff];
			break;

		case 0xa6:      /* AND (HL) */
			AF = andTable[((AF >> 8)& GET_BYTE(HL)) & 0xff];
			break;

		case 0xa7:      /* AND A */
			AF = andTable[(AF >> 8) & 0xff];
			break;

		case 0xa8:      /* XOR B */
			AF = xororTable[((AF ^ BC) >> 8) & 0xff];
			break;

		case 0xa9:      /* XOR C */
			AF = xororTable[((AF >> 8) ^ BC) & 0xff];
			break;

		case 0xaa:      /* XOR D */
			AF = xororTable[((AF ^ DE) >> 8) & 0xff];
			break;

		case 0xab:      /* XOR E */
			AF = xororTable[((AF >> 8) ^ DE) & 0xff];
			break;

		case 0xac:      /* XOR H */
			AF = xororTable[((AF ^ HL) >> 8) & 0xff];
			break;

		case 0xad:      /* XOR L */
			AF = xororTable[((AF >> 8) ^ HL) & 0xff];
			break;

		case 0xae:      /* XOR (HL) */
			AF = xororTable[((AF >> 8) ^ GET_BYTE(HL)) & 0xff];
			break;

		case 0xaf:      /* XOR A */
			AF = 0x44;
			break;

		case 0xb0:      /* OR B */
			AF = xororTable[((AF | BC) >> 8) & 0xff];
			break;

		case 0xb1:      /* OR C */
			AF = xororTable[((AF >> 8) | BC) & 0xff];
			break;

		case 0xb2:      /* OR D */
			AF = xororTable[((AF | DE) >> 8) & 0xff];
			break;

		case 0xb3:      /* OR E */
			AF = xororTable[((AF >> 8) | DE) & 0xff];
			break;

		case 0xb4:      /* OR H */
			AF = xororTable[((AF | HL) >> 8) & 0xff];
			break;

		case 0xb5:      /* OR L */
			AF = xororTable[((AF >> 8) | HL) & 0xff];
			break;

		case 0xb6:      /* OR (HL) */
			AF = xororTable[((AF >> 8) | GET_BYTE(HL)) & 0xff];
			break;

		case 0xb7:      /* OR A */
			AF = xororTable[(AF >> 8) & 0xff];
			break;

		case 0xb8:      /* CP B */
			temp = HIGH_REGISTER(BC);
			AF = (AF & ~0x28) | (temp & 0x28);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = (AF & ~0xff) | cpTable[sum & 0xff] | (temp & 0x28) |
				(SET_PV) | cbits2Table[cbits & 0x1ff];
			break;

		case 0xb9:      /* CP C */
			temp = LOW_REGISTER(BC);
			AF = (AF & ~0x28) | (temp & 0x28);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = (AF & ~0xff) | cpTable[sum & 0xff] | (temp & 0x28) |
				(SET_PV) | cbits2Table[cbits & 0x1ff];
			break;

		case 0xba:      /* CP D */
			temp = HIGH_REGISTER(DE);
			AF = (AF & ~0x28) | (temp & 0x28);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = (AF & ~0xff) | cpTable[sum & 0xff] | (temp & 0x28) |
				(SET_PV) | cbits2Table[cbits & 0x1ff];
			break;

		case 0xbb:      /* CP E */
			temp = LOW_REGISTER(DE);
			AF = (AF & ~0x28) | (temp & 0x28);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = (AF & ~0xff) | cpTable[sum & 0xff] | (temp & 0x28) |
				(SET_PV) | cbits2Table[cbits & 0x1ff];
			break;

		case 0xbc:      /* CP H */
			temp = HIGH_REGISTER(HL);
			AF = (AF & ~0x28) | (temp & 0x28);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = (AF & ~0xff) | cpTable[sum & 0xff] | (temp & 0x28) |
				(SET_PV) | cbits2Table[cbits & 0x1ff];
			break;

		case 0xbd:      /* CP L */
			temp = LOW_REGISTER(HL);
			AF = (AF & ~0x28) | (temp & 0x28);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = (AF & ~0xff) | cpTable[sum & 0xff] | (temp & 0x28) |
				(SET_PV) | cbits2Table[cbits & 0x1ff];
			break;

		case 0xbe:      /* CP (HL) */
			temp = GET_BYTE(HL);
			AF = (AF & ~0x28) | (temp & 0x28);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = (AF & ~0xff) | cpTable[sum & 0xff] | (temp & 0x28) |
				(SET_PV) | cbits2Table[cbits & 0x1ff];
			break;

		case 0xbf:      /* CP A */
			SET_LOW_REGISTER(AF, (HIGH_REGISTER(AF) & 0x28) | 0x42);
			break;

		case 0xc0:      /* RET NZ */
			if (!(TSTFLAG(Z)))
				POP(PC);
			break;

		case 0xc1:      /* POP BC */
			POP(BC);
			break;

		case 0xc2:      /* JP NZ,nnnn */
			JPC(!TSTFLAG(Z));
			break;

		case 0xc3:      /* JP nnnn */
			JPC(1);
			break;

		case 0xc4:      /* CALL NZ,nnnn */
			CALLC(!TSTFLAG(Z));
			break;

		case 0xc5:      /* PUSH BC */
			PUSH(BC);
			break;

		case 0xc6:      /* ADD A,nn */
			temp = RAM_PP(PC);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp;
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0xc7:      /* RST 0 */
			PUSH(PC);
			PC = 0;
			break;

		case 0xc8:      /* RET Z */
			if (TSTFLAG(Z))
				POP(PC);
			break;

		case 0xc9:      /* RET */
			POP(PC);
			break;

		case 0xca:      /* JP Z,nnnn */
			JPC(TSTFLAG(Z));
			break;

		case 0xcb:      /* CB prefix */
			INCR(1); /* Add one M1 cycle to refresh counter */
			adr = HL;
			switch ((op = GET_BYTE(PC)) & 7) {

			case 0:
				acu = HIGH_REGISTER(BC);
				break;

			case 1:
				acu = LOW_REGISTER(BC);
				break;

			case 2:
				acu = HIGH_REGISTER(DE);
				break;

			case 3:
				acu = LOW_REGISTER(DE);
				break;

			case 4:
				acu = HIGH_REGISTER(HL);
				break;

			case 5:
				acu = LOW_REGISTER(HL);
				break;

			case 6:
				acu = GET_BYTE(adr);
				break;

			default:
				acu = HIGH_REGISTER(AF);
				break;
			}
			++PC;
			switch (op & 0xc0) {

			case 0x00:  /* shift/rotate */
				switch (op & 0x38) {

					case 0x00:/* RLC */
						temp = (acu << 1) | (acu >> 7);
						cbits = temp & 1;
						break;

					case 0x08:/* RRC */
						temp = (acu >> 1) | (acu << 7);
						cbits = temp & 0x80;
						break;

					case 0x10:/* RL */
						temp = (acu << 1) | TSTFLAG(C);
						cbits = acu & 0x80;
						break;

					case 0x18:/* RR */
						temp = (acu >> 1) | (TSTFLAG(C) << 7);
						cbits = acu & 1;
						break;

					case 0x20:/* SLA */
						temp = acu << 1;
						cbits = acu & 0x80;
						break;

					case 0x28:/* SRA */
						temp = (acu >> 1) | (acu & 0x80);
						cbits = acu & 1;
						break;

					case 0x30:/* SLIA */
						temp = (acu << 1) | 1;
						cbits = acu & 0x80;
						break;

					case 0x38:/* SRL */
						temp = acu >> 1;
						cbits = acu & 1;
						break;

					default:
						temp = acu;
						cbits = 0;
					}
					AF = (AF & ~0xff) | rotateShiftTable[temp & 0xff] | !!cbits;
				break;

			case 0x40:  /* BIT */
				if (acu & (1 << ((op >> 3) & 7)))
					AF = (AF & ~0xfe) | 0x10 | (((op & 0x38) == 0x38) << 7);
				else
					AF = (AF & ~0xfe) | 0x54;
				if ((op & 7) != 6)
					AF |= (acu & 0x28);
				temp = acu;
				break;

			case 0x80:  /* RES */
				temp = acu & ~(1 << ((op >> 3) & 7));
				break;

			case 0xc0:  /* SET */
				temp = acu | (1 << ((op >> 3) & 7));
				break;
			}
			switch (op & 7) {

			case 0:
				SET_HIGH_REGISTER(BC, temp);
				break;

			case 1:
				SET_LOW_REGISTER(BC, temp);
				break;

			case 2:
				SET_HIGH_REGISTER(DE, temp);
				break;

			case 3:
				SET_LOW_REGISTER(DE, temp);
				break;

			case 4:
				SET_HIGH_REGISTER(HL, temp);
				break;

			case 5:
				SET_LOW_REGISTER(HL, temp);
				break;

			case 6:
				PUT_BYTE(adr, temp);
				break;

			default:
				SET_HIGH_REGISTER(AF, temp);
				break;
			}
			break;

		case 0xcc:      /* CALL Z,nnnn */
			CALLC(TSTFLAG(Z));
			break;

		case 0xcd:      /* CALL nnnn */
			CALLC(1);
			break;

		case 0xce:      /* ADC A,nn */
			temp = RAM_PP(PC);
			acu = HIGH_REGISTER(AF);
			sum = acu + temp + TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = addTable[sum] | cbitsTable[cbits] | (SET_PV);
			break;

		case 0xcf:      /* RST 8 */
			PUSH(PC);
			PC = 8;
			break;

		case 0xd0:      /* RET NC */
			if (!(TSTFLAG(C)))
				POP(PC);
			break;

		case 0xd1:      /* POP DE */
			POP(DE);
			break;

		case 0xd2:      /* JP NC,nnnn */
			JPC(!TSTFLAG(C));
			break;

		case 0xd3:      /* OUT (nn),A */
			cpu_out(RAM_PP(PC), HIGH_REGISTER(AF));
			break;

		case 0xd4:      /* CALL NC,nnnn */
			CALLC(!TSTFLAG(C));
			break;

		case 0xd5:      /* PUSH DE */
			PUSH(DE);
			break;

		case 0xd6:      /* SUB nn */
			temp = RAM_PP(PC);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0xd7:      /* RST 10H */
			PUSH(PC);
			PC = 0x10;
			break;

		case 0xd8:      /* RET C */
			if (TSTFLAG(C))
				POP(PC);
			break;

		case 0xd9:      /* EXX */
			BC ^= BC1;
			BC1 ^= BC;
			BC ^= BC1;
			DE ^= DE1;
			DE1 ^= DE;
			DE ^= DE1;
			HL ^= HL1;
			HL1 ^= HL;
			HL ^= HL1;
			break;

		case 0xda:      /* JP C,nnnn */
			JPC(TSTFLAG(C));
			break;

		case 0xdb:      /* IN A,(nn) */
			SET_HIGH_REGISTER(AF, cpu_in(RAM_PP(PC)));
			break;

		case 0xdc:      /* CALL C,nnnn */
			CALLC(TSTFLAG(C));
			break;

		case 0xdd:      /* DD prefix */
			INCR(1); /* Add one M1 cycle to refresh counter */
			switch (RAM_PP(PC)) {

			case 0x09:      /* ADD IX,BC */
				IX &= ADDRMASK;
				BC &= ADDRMASK;
				sum = IX + BC;
				AF = (AF & ~0x3b) | ((sum >> 8) & 0x28) | cbitsTable[(IX ^ BC ^ sum) >> 8];
				IX = sum;
				break;

			case 0x19:      /* ADD IX,DE */
				IX &= ADDRMASK;
				DE &= ADDRMASK;
				sum = IX + DE;
				AF = (AF & ~0x3b) | ((sum >> 8) & 0x28) | cbitsTable[(IX ^ DE ^ sum) >> 8];
				IX = sum;
				break;

			case 0x21:      /* LD IX,nnnn */
				IX = GET_WORD(PC++);
				++PC;
				break;

			case 0x22:      /* LD (nnnn),IX */
				PUT_WORD(GET_WORD(PC++), IX);
				++PC;
				break;

			case 0x23:      /* INC IX */
				++IX;
				break;

			case 0x24:      /* INC IXH */
				IX += 0x100;
				AF = (AF & ~0xfe) | incZ80Table[HIGH_REGISTER(IX)];
				break;

			case 0x25:      /* DEC IXH */
				IX -= 0x100;
				AF = (AF & ~0xfe) | decZ80Table[HIGH_REGISTER(IX)];
				break;

			case 0x26:      /* LD IXH,nn */
				SET_HIGH_REGISTER(IX, RAM_PP(PC));
				break;

			case 0x29:      /* ADD IX,IX */
				IX &= ADDRMASK;
				sum = IX + IX;
				AF = (AF & ~0x3b) | cbitsDup16Table[sum >> 8];
				IX = sum;
				break;

			case 0x2a:      /* LD IX,(nnnn) */
				IX = GET_WORD(GET_WORD(PC++));
				++PC;
				break;

			case 0x2b:      /* DEC IX */
				--IX;
				break;

			case 0x2c:      /* INC IXL */
				temp = LOW_REGISTER(IX) + 1;
				SET_LOW_REGISTER(IX, temp);
				AF = (AF & ~0xfe) | incZ80Table[temp];
				break;

			case 0x2d:      /* DEC IXL */
				temp = LOW_REGISTER(IX) - 1;
				SET_LOW_REGISTER(IX, temp);
				AF = (AF & ~0xfe) | decZ80Table[temp & 0xff];
				break;

			case 0x2e:      /* LD IXL,nn */
				SET_LOW_REGISTER(IX, RAM_PP(PC));
				break;

			case 0x34:      /* INC (IX+dd) */
				adr = IX + (int8)RAM_PP(PC);
				temp = GET_BYTE(adr) + 1;
				PUT_BYTE(adr, temp);
				AF = (AF & ~0xfe) | incZ80Table[temp];
				break;

			case 0x35:      /* DEC (IX+dd) */
				adr = IX + (int8)RAM_PP(PC);
				temp = GET_BYTE(adr) - 1;
				PUT_BYTE(adr, temp);
				AF = (AF & ~0xfe) | decZ80Table[temp & 0xff];
				break;

			case 0x36:      /* LD (IX+dd),nn */
				adr = IX + (int8)RAM_PP(PC);
				PUT_BYTE(adr, RAM_PP(PC));
				break;

			case 0x39:      /* ADD IX,SP */
				IX &= ADDRMASK;
				SP &= ADDRMASK;
				sum = IX + SP;
				AF = (AF & ~0x3b) | ((sum >> 8) & 0x28) | cbitsTable[(IX ^ SP ^ sum) >> 8];
				IX = sum;
				break;

			case 0x44:      /* LD B,IXH */
				SET_HIGH_REGISTER(BC, HIGH_REGISTER(IX));
				break;

			case 0x45:      /* LD B,IXL */
				SET_HIGH_REGISTER(BC, LOW_REGISTER(IX));
				break;

			case 0x46:      /* LD B,(IX+dd) */
				SET_HIGH_REGISTER(BC, GET_BYTE(IX + (int8)RAM_PP(PC)));
				break;

			case 0x4c:      /* LD C,IXH */
				SET_LOW_REGISTER(BC, HIGH_REGISTER(IX));
				break;

			case 0x4d:      /* LD C,IXL */
				SET_LOW_REGISTER(BC, LOW_REGISTER(IX));
				break;

			case 0x4e:      /* LD C,(IX+dd) */
				SET_LOW_REGISTER(BC, GET_BYTE(IX + (int8)RAM_PP(PC)));
				break;

			case 0x54:      /* LD D,IXH */
				SET_HIGH_REGISTER(DE, HIGH_REGISTER(IX));
				break;

			case 0x55:      /* LD D,IXL */
				SET_HIGH_REGISTER(DE, LOW_REGISTER(IX));
				break;

			case 0x56:      /* LD D,(IX+dd) */
				SET_HIGH_REGISTER(DE, GET_BYTE(IX + (int8)RAM_PP(PC)));
				break;

			case 0x5c:      /* LD E,IXH */
				SET_LOW_REGISTER(DE, HIGH_REGISTER(IX));
				break;

			case 0x5d:      /* LD E,IXL */
				SET_LOW_REGISTER(DE, LOW_REGISTER(IX));
				break;

			case 0x5e:      /* LD E,(IX+dd) */
				SET_LOW_REGISTER(DE, GET_BYTE(IX + (int8)RAM_PP(PC)));
				break;

			case 0x60:      /* LD IXH,B */
				SET_HIGH_REGISTER(IX, HIGH_REGISTER(BC));
				break;

			case 0x61:      /* LD IXH,C */
				SET_HIGH_REGISTER(IX, LOW_REGISTER(BC));
				break;

			case 0x62:      /* LD IXH,D */
				SET_HIGH_REGISTER(IX, HIGH_REGISTER(DE));
				break;

			case 0x63:      /* LD IXH,E */
				SET_HIGH_REGISTER(IX, LOW_REGISTER(DE));
				break;

			case 0x64:      /* LD IXH,IXH */
				break;

			case 0x65:      /* LD IXH,IXL */
				SET_HIGH_REGISTER(IX, LOW_REGISTER(IX));
				break;

			case 0x66:      /* LD H,(IX+dd) */
				SET_HIGH_REGISTER(HL, GET_BYTE(IX + (int8)RAM_PP(PC)));
				break;

			case 0x67:      /* LD IXH,A */
				SET_HIGH_REGISTER(IX, HIGH_REGISTER(AF));
				break;

			case 0x68:      /* LD IXL,B */
				SET_LOW_REGISTER(IX, HIGH_REGISTER(BC));
				break;

			case 0x69:      /* LD IXL,C */
				SET_LOW_REGISTER(IX, LOW_REGISTER(BC));
				break;

			case 0x6a:      /* LD IXL,D */
				SET_LOW_REGISTER(IX, HIGH_REGISTER(DE));
				break;

			case 0x6b:      /* LD IXL,E */
				SET_LOW_REGISTER(IX, LOW_REGISTER(DE));
				break;

			case 0x6c:      /* LD IXL,IXH */
				SET_LOW_REGISTER(IX, HIGH_REGISTER(IX));
				break;

			case 0x6d:      /* LD IXL,IXL */
				break;

			case 0x6e:      /* LD L,(IX+dd) */
				SET_LOW_REGISTER(HL, GET_BYTE(IX + (int8)RAM_PP(PC)));
				break;

			case 0x6f:      /* LD IXL,A */
				SET_LOW_REGISTER(IX, HIGH_REGISTER(AF));
				break;

			case 0x70:      /* LD (IX+dd),B */
				PUT_BYTE(IX + (int8)RAM_PP(PC), HIGH_REGISTER(BC));
				break;

			case 0x71:      /* LD (IX+dd),C */
				PUT_BYTE(IX + (int8)RAM_PP(PC), LOW_REGISTER(BC));
				break;

			case 0x72:      /* LD (IX+dd),D */
				PUT_BYTE(IX + (int8)RAM_PP(PC), HIGH_REGISTER(DE));
				break;

			case 0x73:      /* LD (IX+dd),E */
				PUT_BYTE(IX + (int8)RAM_PP(PC), LOW_REGISTER(DE));
				break;

			case 0x74:      /* LD (IX+dd),H */
				PUT_BYTE(IX + (int8)RAM_PP(PC), HIGH_REGISTER(HL));
				break;

			case 0x75:      /* LD (IX+dd),L */
				PUT_BYTE(IX + (int8)RAM_PP(PC), LOW_REGISTER(HL));
				break;

			case 0x77:      /* LD (IX+dd),A */
				PUT_BYTE(IX + (int8)RAM_PP(PC), HIGH_REGISTER(AF));
				break;

			case 0x7c:      /* LD A,IXH */
				SET_HIGH_REGISTER(AF, HIGH_REGISTER(IX));
				break;

			case 0x7d:      /* LD A,IXL */
				SET_HIGH_REGISTER(AF, LOW_REGISTER(IX));
				break;

			case 0x7e:      /* LD A,(IX+dd) */
				SET_HIGH_REGISTER(AF, GET_BYTE(IX + (int8)RAM_PP(PC)));
				break;

			case 0x84:      /* ADD A,IXH */
				temp = HIGH_REGISTER(IX);
				acu = HIGH_REGISTER(AF);
				sum = acu + temp;
				AF = addTable[sum] | cbitsZ80Table[acu ^ temp ^ sum];
				break;

			case 0x85:      /* ADD A,IXL */
				temp = LOW_REGISTER(IX);
				acu = HIGH_REGISTER(AF);
				sum = acu + temp;
				AF = addTable[sum] | cbitsZ80Table[acu ^ temp ^ sum];
				break;

			case 0x86:      /* ADD A,(IX+dd) */
				adr = IX + (int8)RAM_PP(PC);
				temp = GET_BYTE(adr);
				acu = HIGH_REGISTER(AF);
				sum = acu + temp;
				AF = addTable[sum] | cbitsZ80Table[acu ^ temp ^ sum];
				break;

			case 0x8c:      /* ADC A,IXH */
				temp = HIGH_REGISTER(IX);
				acu = HIGH_REGISTER(AF);
				sum = acu + temp + TSTFLAG(C);
				AF = addTable[sum] | cbitsZ80Table[acu ^ temp ^ sum];
				break;

			case 0x8d:      /* ADC A,IXL */
				temp = LOW_REGISTER(IX);
				acu = HIGH_REGISTER(AF);
				sum = acu + temp + TSTFLAG(C);
				AF = addTable[sum] | cbitsZ80Table[acu ^ temp ^ sum];
				break;

			case 0x8e:      /* ADC A,(IX+dd) */
				adr = IX + (int8)RAM_PP(PC);
				temp = GET_BYTE(adr);
				acu = HIGH_REGISTER(AF);
				sum = acu + temp + TSTFLAG(C);
				AF = addTable[sum] | cbitsZ80Table[acu ^ temp ^ sum];
				break;

			case 0x96:      /* SUB (IX+dd) */
				adr = IX + (int8)RAM_PP(PC);
				temp = GET_BYTE(adr);
				acu = HIGH_REGISTER(AF);
				sum = acu - temp;
				AF = addTable[sum & 0xff] | cbits2Z80Table[(acu ^ temp ^ sum) & 0x1ff];
				break;

			case 0x94:      /* SUB IXH */
				SETFLAG(C, 0);
				__attribute__((fallthrough));/* a bit less efficient but smaller code */

			case 0x9c:      /* SBC A,IXH */
				temp = HIGH_REGISTER(IX);
				acu = HIGH_REGISTER(AF);
				sum = acu - temp - TSTFLAG(C);
				AF = addTable[sum & 0xff] | cbits2Z80Table[(acu ^ temp ^ sum) & 0x1ff];
				break;

			case 0x95:      /* SUB IXL */
				SETFLAG(C, 0);
				__attribute__((fallthrough));/* a bit less efficient but smaller code */

			case 0x9d:      /* SBC A,IXL */
				temp = LOW_REGISTER(IX);
				acu = HIGH_REGISTER(AF);
				sum = acu - temp - TSTFLAG(C);
				AF = addTable[sum & 0xff] | cbits2Z80Table[(acu ^ temp ^ sum) & 0x1ff];
				break;

			case 0x9e:      /* SBC A,(IX+dd) */
				adr = IX + (int8)RAM_PP(PC);
				temp = GET_BYTE(adr);
				acu = HIGH_REGISTER(AF);
				sum = acu - temp - TSTFLAG(C);
				AF = addTable[sum & 0xff] | cbits2Z80Table[(acu ^ temp ^ sum) & 0x1ff];
				break;

			case 0xa4:      /* AND IXH */
				AF = andTable[((AF & IX) >> 8) & 0xff];
				break;

			case 0xa5:      /* AND IXL */
				AF = andTable[((AF >> 8)& IX) & 0xff];
				break;

			case 0xa6:      /* AND (IX+dd) */
				AF = andTable[((AF >> 8)& GET_BYTE(IX + (int8)RAM_PP(PC))) & 0xff];
				break;

			case 0xac:      /* XOR IXH */
				AF = xororTable[((AF ^ IX) >> 8) & 0xff];
				break;

			case 0xad:      /* XOR IXL */
				AF = xororTable[((AF >> 8) ^ IX) & 0xff];
				break;

			case 0xae:      /* XOR (IX+dd) */
				AF = xororTable[((AF >> 8) ^ GET_BYTE(IX + (int8)RAM_PP(PC))) & 0xff];
				break;

			case 0xb4:      /* OR IXH */
				AF = xororTable[((AF | IX) >> 8) & 0xff];
				break;

			case 0xb5:      /* OR IXL */
				AF = xororTable[((AF >> 8) | IX) & 0xff];
				break;

			case 0xb6:      /* OR (IX+dd) */
				AF = xororTable[((AF >> 8) | GET_BYTE(IX + (int8)RAM_PP(PC))) & 0xff];
				break;

			case 0xbc:      /* CP IXH */
				temp = HIGH_REGISTER(IX);
				AF = (AF & ~0x28) | (temp & 0x28);
				acu = HIGH_REGISTER(AF);
				sum = acu - temp;
				AF = (AF & ~0xff) | cpTable[sum & 0xff] | (temp & 0x28) |
					cbits2Z80Table[(acu ^ temp ^ sum) & 0x1ff];
				break;

			case 0xbd:      /* CP IXL */
				temp = LOW_REGISTER(IX);
				AF = (AF & ~0x28) | (temp & 0x28);
				acu = HIGH_REGISTER(AF);
				sum = acu - temp;
				AF = (AF & ~0xff) | cpTable[sum & 0xff] | (temp & 0x28) |
					cbits2Z80Table[(acu ^ temp ^ sum) & 0x1ff];
				break;

			case 0xbe:      /* CP (IX+dd) */
				adr = IX + (int8)RAM_PP(PC);
				temp = GET_BYTE(adr);
				AF = (AF & ~0x28) | (temp & 0x28);
				acu = HIGH_REGISTER(AF);
				sum = acu - temp;
				AF = (AF & ~0xff) | cpTable[sum & 0xff] | (temp & 0x28) |
					cbits2Z80Table[(acu ^ temp ^ sum) & 0x1ff];
				break;

			case 0xcb:      /* CB prefix */
				adr = IX + (int8)RAM_PP(PC);
				switch ((op = GET_BYTE(PC)) & 7) {

				case 0:
					acu = HIGH_REGISTER(BC);
					break;

				case 1:
					acu = LOW_REGISTER(BC);
					break;

				case 2:
					acu = HIGH_REGISTER(DE);
					break;

				case 3:
					acu = LOW_REGISTER(DE);
					break;

				case 4:
					acu = HIGH_REGISTER(HL);
					break;

				case 5:
					acu = LOW_REGISTER(HL);
					break;

				case 6:
					acu = GET_BYTE(adr);
					break;

				default:
					acu = HIGH_REGISTER(AF);
					break;
				}
				++PC;
				switch (op & 0xc0) {

				case 0x00:  /* shift/rotate */
					switch (op & 0x38) {

						case 0x00:/* RLC */
							temp = (acu << 1) | (acu >> 7);
							cbits = temp & 1;
							break;

						case 0x08:/* RRC */
							temp = (acu >> 1) | (acu << 7);
							cbits = temp & 0x80;
							break;

						case 0x10:/* RL */
							temp = (acu << 1) | TSTFLAG(C);
							cbits = acu & 0x80;
							break;

						case 0x18:/* RR */
							temp = (acu >> 1) | (TSTFLAG(C) << 7);
							cbits = acu & 1;
							break;

						case 0x20:/* SLA */
							temp = acu << 1;
							cbits = acu & 0x80;
							break;

						case 0x28:/* SRA */
							temp = (acu >> 1) | (acu & 0x80);
							cbits = acu & 1;
							break;

						case 0x30:/* SLIA */
							temp = (acu << 1) | 1;
							cbits = acu & 0x80;
							break;

						case 0x38:/* SRL */
							temp = acu >> 1;
							cbits = acu & 1;
							break;

						default:
							temp = acu;
							cbits = 0;
					}
					AF = (AF & ~0xff) | rotateShiftTable[temp & 0xff] | !!cbits;
					break;

				case 0x40:  /* BIT */
					if (acu & (1 << ((op >> 3) & 7)))
						AF = (AF & ~0xfe) | 0x10 | (((op & 0x38) == 0x38) << 7);
					else
						AF = (AF & ~0xfe) | 0x54;
					if ((op & 7) != 6)
						AF |= (acu & 0x28);
					temp = acu;
					break;

				case 0x80:  /* RES */
					temp = acu & ~(1 << ((op >> 3) & 7));
					break;

				case 0xc0:  /* SET */
					temp = acu | (1 << ((op >> 3) & 7));
					break;
				}
				switch (op & 7) {

				case 0:
					SET_HIGH_REGISTER(BC, temp);
					break;

				case 1:
					SET_LOW_REGISTER(BC, temp);
					break;

				case 2:
					SET_HIGH_REGISTER(DE, temp);
					break;

				case 3:
					SET_LOW_REGISTER(DE, temp);
					break;

				case 4:
					SET_HIGH_REGISTER(HL, temp);
					break;

				case 5:
					SET_LOW_REGISTER(HL, temp);
					break;

				case 6:
					PUT_BYTE(adr, temp);
					break;

				default:
					SET_HIGH_REGISTER(AF, temp);
					break;
				}
				break;

			case 0xe1:      /* POP IX */
				POP(IX);
				break;

			case 0xe3:      /* EX (SP),IX */
				temp = IX;
				POP(IX);
				PUSH(temp);
				break;

			case 0xe5:      /* PUSH IX */
				PUSH(IX);
				break;

			case 0xe9:      /* JP (IX) */
				PC = IX;
				break;

			case 0xf9:      /* LD SP,IX */
				SP = IX;
				break;

			default:                /* ignore DD */
				PC = (PC - 1) & 0xffff;
			}
			break;

		case 0xde:          /* SBC A,nn */
			temp = RAM_PP(PC);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp - TSTFLAG(C);
			cbits = acu ^ temp ^ sum;
			AF = subTable[sum & 0xff] | cbitsTable[cbits & 0x1ff] | (SET_PV);
			break;

		case 0xdf:      /* RST 18H */
			PUSH(PC);
			PC = 0x18;
			break;

		case 0xe0:      /* RET PO */
			if (!(TSTFLAG(P)))
				POP(PC);
			break;

		case 0xe1:      /* POP HL */
			POP(HL);
			break;

		case 0xe2:      /* JP PO,nnnn */
			JPC(!TSTFLAG(P));
			break;

		case 0xe3:      /* EX (SP),HL */
			temp = HL;
			POP(HL);
			PUSH(temp);
			break;

		case 0xe4:      /* CALL PO,nnnn */
			CALLC(!TSTFLAG(P));
			break;

		case 0xe5:      /* PUSH HL */
			PUSH(HL);
			break;

		case 0xe6:      /* AND nn */
			AF = andTable[((AF >> 8)& RAM_PP(PC)) & 0xff];
			break;

		case 0xe7:      /* RST 20H */
			PUSH(PC);
			PC = 0x20;
			break;

		case 0xe8:      /* RET PE */
			if (TSTFLAG(P))
				POP(PC);
			break;

		case 0xe9:      /* JP (HL) */
			PC = HL;
			break;

		case 0xea:      /* JP PE,nnnn */
			JPC(TSTFLAG(P));
			break;

		case 0xeb:      /* EX DE,HL */
			HL ^= DE;
			DE ^= HL;
			HL ^= DE;
			break;

		case 0xec:      /* CALL PE,nnnn */
			CALLC(TSTFLAG(P));
			break;

		case 0xed:      /* ED prefix */
			INCR(1); /* Add one M1 cycle to refresh counter */
			switch (RAM_PP(PC)) {

			case 0x40:      /* IN B,(C) */
				temp = cpu_in(LOW_REGISTER(BC));
				SET_HIGH_REGISTER(BC, temp);
				AF = (AF & ~0xfe) | rotateShiftTable[temp & 0xff];
				break;

			case 0x41:      /* OUT (C),B */
				cpu_out(LOW_REGISTER(BC), HIGH_REGISTER(BC));
				break;

			case 0x42:      /* SBC HL,BC */
				HL &= ADDRMASK;
				BC &= ADDRMASK;
				sum = HL - BC - TSTFLAG(C);
				AF = (AF & ~0xff) | ((sum >> 8) & 0xa8) | (((sum & ADDRMASK) == 0) << 6) |
					cbits2Z80Table[((HL ^ BC ^ sum) >> 8) & 0x1ff];
				HL = sum;
				break;

			case 0x43:      /* LD (nnnn),BC */
				PUT_WORD(GET_WORD(PC++), BC);
				++PC;
				break;

			case 0x44:      /* NEG */

			case 0x4C:      /* NEG, unofficial */

			case 0x54:      /* NEG, unofficial */

			case 0x5C:      /* NEG, unofficial */

			case 0x64:      /* NEG, unofficial */

			case 0x6C:      /* NEG, unofficial */

			case 0x74:      /* NEG, unofficial */

			case 0x7C:      /* NEG, unofficial */
				temp = HIGH_REGISTER(AF);
				AF = ((~(AF & 0xff00) + 1) & 0xff00); /* AF = (-(AF & 0xff00) & 0xff00); */
				AF |= ((AF >> 8) & 0xa8) | (((AF & 0xff00) == 0) << 6) | negTable[temp];
				break;

			case 0x45:      /* RETN */

			case 0x55:      /* RETN, unofficial */

			case 0x5D:      /* RETN, unofficial */

			case 0x65:      /* RETN, unofficial */

			case 0x6D:      /* RETN, unofficial */

			case 0x75:      /* RETN, unofficial */

			case 0x7D:      /* RETN, unofficial */
				IFF |= IFF >> 1;
				POP(PC);
				break;

			case 0x46:      /* IM 0 */
							/* interrupt mode 0 */
				break;

			case 0x47:      /* LD I,A */
				IR = (IR & 0xff) | (AF & ~0xff);
				break;

			case 0x48:      /* IN C,(C) */
				temp = cpu_in(LOW_REGISTER(BC));
				SET_LOW_REGISTER(BC, temp);
				AF = (AF & ~0xfe) | rotateShiftTable[temp & 0xff];
				break;

			case 0x49:      /* OUT (C),C */
				cpu_out(LOW_REGISTER(BC), LOW_REGISTER(BC));
				break;

			case 0x4a:      /* ADC HL,BC */
				HL &= ADDRMASK;
				BC &= ADDRMASK;
				sum = HL + BC + TSTFLAG(C);
				AF = (AF & ~0xff) | ((sum >> 8) & 0xa8) | (((sum & ADDRMASK) == 0) << 6) |
					cbitsZ80Table[(HL ^ BC ^ sum) >> 8];
				HL = sum;
				break;

			case 0x4b:      /* LD BC,(nnnn) */
				BC = GET_WORD(GET_WORD(PC++));
				++PC;
				break;

			case 0x4d:      /* RETI */
				IFF |= IFF >> 1;
				POP(PC);
				break;

			case 0x4f:      /* LD R,A */
				IR = (IR & ~0xff) | ((AF >> 8) & 0xff);
				break;

			case 0x50:      /* IN D,(C) */
				temp = cpu_in(LOW_REGISTER(BC));
				SET_HIGH_REGISTER(DE, temp);
				AF = (AF & ~0xfe) | rotateShiftTable[temp & 0xff];
				break;

			case 0x51:      /* OUT (C),D */
				cpu_out(LOW_REGISTER(BC), HIGH_REGISTER(DE));
				break;

			case 0x52:      /* SBC HL,DE */
				HL &= ADDRMASK;
				DE &= ADDRMASK;
				sum = HL - DE - TSTFLAG(C);
				AF = (AF & ~0xff) | ((sum >> 8) & 0xa8) | (((sum & ADDRMASK) == 0) << 6) |
					cbits2Z80Table[((HL ^ DE ^ sum) >> 8) & 0x1ff];
				HL = sum;
				break;

			case 0x53:      /* LD (nnnn),DE */
				PUT_WORD(GET_WORD(PC++), DE);
				++PC;
				break;

			case 0x56:      /* IM 1 */
							/* interrupt mode 1 */
				break;

			case 0x57:      /* LD A,I */
				AF = (AF & 0x29) | (IR & ~0xff) | ((IR >> 8) & 0x80) | (((IR & ~0xff) == 0) << 6) | ((IFF & 2) << 1);
				break;

			case 0x58:      /* IN E,(C) */
				temp = cpu_in(LOW_REGISTER(BC));
				SET_LOW_REGISTER(DE, temp);
				AF = (AF & ~0xfe) | rotateShiftTable[temp & 0xff];
				break;

			case 0x59:      /* OUT (C),E */
				cpu_out(LOW_REGISTER(BC), LOW_REGISTER(DE));
				break;

			case 0x5a:      /* ADC HL,DE */
				HL &= ADDRMASK;
				DE &= ADDRMASK;
				sum = HL + DE + TSTFLAG(C);
				AF = (AF & ~0xff) | ((sum >> 8) & 0xa8) | (((sum & ADDRMASK) == 0) << 6) |
					cbitsZ80Table[(HL ^ DE ^ sum) >> 8];
				HL = sum;
				break;

			case 0x5b:      /* LD DE,(nnnn) */
				DE = GET_WORD(GET_WORD(PC++));
				++PC;
				break;

			case 0x5e:      /* IM 2 */
							/* interrupt mode 2 */
				break;

			case 0x5f:      /* LD A,R */
				AF = (AF & 0x29) | ((IR & 0xff) << 8) | (IR & 0x80) |
					(((IR & 0xff) == 0) << 6) | ((IFF & 2) << 1);
				break;

			case 0x60:      /* IN H,(C) */
				temp = cpu_in(LOW_REGISTER(BC));
				SET_HIGH_REGISTER(HL, temp);
				AF = (AF & ~0xfe) | rotateShiftTable[temp & 0xff];
				break;

			case 0x61:      /* OUT (C),H */
				cpu_out(LOW_REGISTER(BC), HIGH_REGISTER(HL));
				break;

			case 0x62:      /* SBC HL,HL */
				HL &= ADDRMASK;
				sum = HL - HL - TSTFLAG(C);
				AF = (AF & ~0xff) | (((sum & ADDRMASK) == 0) << 6) |
					cbits2Z80DupTable[(sum >> 8) & 0x1ff];
				HL = sum;
				break;

			case 0x63:      /* LD (nnnn),HL */
				PUT_WORD(GET_WORD(PC++), HL);
				++PC;
				break;

			case 0x67:      /* RRD */
				temp = GET_BYTE(HL);
				acu = HIGH_REGISTER(AF);
				PUT_BYTE(HL, HIGH_DIGIT(temp) | (LOW_DIGIT(acu) << 4));
				AF = rrdrldTable[(acu & 0xf0) | LOW_DIGIT(temp)] | (AF & 1);
				break;

			case 0x68:      /* IN L,(C) */
				temp = cpu_in(LOW_REGISTER(BC));
				SET_LOW_REGISTER(HL, temp);
				AF = (AF & ~0xfe) | rotateShiftTable[temp & 0xff];
				break;

			case 0x69:      /* OUT (C),L */
				cpu_out(LOW_REGISTER(BC), LOW_REGISTER(HL));
				break;

			case 0x6a:      /* ADC HL,HL */
				HL &= ADDRMASK;
				sum = HL + HL + TSTFLAG(C);
				AF = (AF & ~0xff) | (((sum & ADDRMASK) == 0) << 6) |
					cbitsZ80DupTable[sum >> 8];
				HL = sum;
				break;

			case 0x6b:      /* LD HL,(nnnn) */
				HL = GET_WORD(GET_WORD(PC++));
				++PC;
				break;

			case 0x6f:      /* RLD */
				temp = GET_BYTE(HL);
				acu = HIGH_REGISTER(AF);
				PUT_BYTE(HL, (LOW_DIGIT(temp) << 4) | LOW_DIGIT(acu));
				AF = rrdrldTable[(acu & 0xf0) | HIGH_DIGIT(temp)] | (AF & 1);
				break;

			case 0x70:      /* IN (C) */
				temp = cpu_in(LOW_REGISTER(BC));
				SET_LOW_REGISTER(temp, temp);
				AF = (AF & ~0xfe) | rotateShiftTable[temp & 0xff];
				break;

			case 0x71:      /* OUT (C),0 */
				cpu_out(LOW_REGISTER(BC), 0);
				break;

			case 0x72:      /* SBC HL,SP */
				HL &= ADDRMASK;
				SP &= ADDRMASK;
				sum = HL - SP - TSTFLAG(C);
				AF = (AF & ~0xff) | ((sum >> 8) & 0xa8) | (((sum & ADDRMASK) == 0) << 6) |
					cbits2Z80Table[((HL ^ SP ^ sum) >> 8) & 0x1ff];
				HL = sum;
				break;

			case 0x73:      /* LD (nnnn),SP */
				PUT_WORD(GET_WORD(PC++), SP);
				++PC;
				break;

			case 0x78:      /* IN A,(C) */
				temp = cpu_in(LOW_REGISTER(BC));
				SET_HIGH_REGISTER(AF, temp);
				AF = (AF & ~0xfe) | rotateShiftTable[temp & 0xff];
				break;

			case 0x79:      /* OUT (C),A */
				cpu_out(LOW_REGISTER(BC), HIGH_REGISTER(AF));
				break;

			case 0x7a:      /* ADC HL,SP */
				HL &= ADDRMASK;
				SP &= ADDRMASK;
				sum = HL + SP + TSTFLAG(C);
				AF = (AF & ~0xff) | ((sum >> 8) & 0xa8) | (((sum & ADDRMASK) == 0) << 6) |
					cbitsZ80Table[(HL ^ SP ^ sum) >> 8];
				HL = sum;
				break;

			case 0x7b:      /* LD SP,(nnnn) */
				SP = GET_WORD(GET_WORD(PC++));
				++PC;
				break;

			case 0xa0:      /* LDI */
				acu = RAM_PP(HL);
				PUT_BYTE_PP(DE, acu);
				acu += HIGH_REGISTER(AF);
				AF = (AF & ~0x3e) | (acu & 8) | ((acu & 2) << 4) |
					(((--BC & ADDRMASK) != 0) << 2);
				break;

			case 0xa1:      /* CPI */
				acu = HIGH_REGISTER(AF);
				temp = RAM_PP(HL);
				sum = acu - temp;
				cbits = acu ^ temp ^ sum;
				AF = (AF & ~0xfe) | (sum & 0x80) | (!(sum & 0xff) << 6) |
					(((sum - ((cbits & 16) >> 4)) & 2) << 4) | (cbits & 16) |
					((sum - ((cbits >> 4) & 1)) & 8) |
					((--BC & ADDRMASK) != 0) << 2 | 2;
				if ((sum & 15) == 8 && (cbits & 16) != 0)
					AF &= ~8;
				break;

				/*  SF, ZF, YF, XF flags are affected by decreasing register B, as in DEC B.
				NF flag A is copy of bit 7 of the value read from or written to an I/O port.
				INI/INIR/IND/INDR use the C flag in stead of the L register. There is a
				catch though, because not the value of C is used, but C + 1 if it's INI/INIR or
				C - 1 if it's IND/INDR. So, first of all INI/INIR:
				HF and CF Both set if ((HL) + ((C + 1) & 255) > 255)
				PF The parity of (((HL) + ((C + 1) & 255)) & 7) xor B)                      */
			case 0xa2:      /* INI */
				acu = cpu_in(LOW_REGISTER(BC));
				PUT_BYTE(HL, acu);
				++HL;
				temp = HIGH_REGISTER(BC);
				BC -= 0x100;
				INOUTFLAGS_NONZERO((LOW_REGISTER(BC) + 1) & 0xff);
				break;

				/*  SF, ZF, YF, XF flags are affected by decreasing register B, as in DEC B.
				NF flag A is copy of bit 7 of the value read from or written to an I/O port.
				And now the for OUTI/OTIR/OUTD/OTDR instructions. Take state of the L
				after the increment or decrement of HL; add the value written to the I/O port
				to; call that k for now. If k > 255, then the CF and HF flags are set. The PF
				flags is set like the parity of k bitwise and'ed with 7, bitwise xor'ed with B.
				HF and CF Both set if ((HL) + L > 255)
				PF The parity of ((((HL) + L) & 7) xor B)                                       */
			case 0xa3:      /* OUTI */
				acu = GET_BYTE(HL);
				cpu_out(LOW_REGISTER(BC), acu);
				++HL;
				temp = HIGH_REGISTER(BC);
				BC -= 0x100;
				INOUTFLAGS_NONZERO(LOW_REGISTER(HL));
				break;

			case 0xa8:      /* LDD */
				acu = RAM_MM(HL);
				PUT_BYTE_MM(DE, acu);
				acu += HIGH_REGISTER(AF);
				AF = (AF & ~0x3e) | (acu & 8) | ((acu & 2) << 4) |
					(((--BC & ADDRMASK) != 0) << 2);
				break;

			case 0xa9:      /* CPD */
				acu = HIGH_REGISTER(AF);
				temp = RAM_MM(HL);
				sum = acu - temp;
				cbits = acu ^ temp ^ sum;
				AF = (AF & ~0xfe) | (sum & 0x80) | (!(sum & 0xff) << 6) |
					(((sum - ((cbits & 16) >> 4)) & 2) << 4) | (cbits & 16) |
					((sum - ((cbits >> 4) & 1)) & 8) |
					((--BC & ADDRMASK) != 0) << 2 | 2;
				if ((sum & 15) == 8 && (cbits & 16) != 0)
					AF &= ~8;
				break;

				/*  SF, ZF, YF, XF flags are affected by decreasing register B, as in DEC B.
				NF flag A is copy of bit 7 of the value read from or written to an I/O port.
				INI/INIR/IND/INDR use the C flag in stead of the L register. There is a
				catch though, because not the value of C is used, but C + 1 if it's INI/INIR or
				C - 1 if it's IND/INDR. And last IND/INDR:
				HF and CF Both set if ((HL) + ((C - 1) & 255) > 255)
				PF The parity of (((HL) + ((C - 1) & 255)) & 7) xor B)                      */
			case 0xaa:      /* IND */
				acu = cpu_in(LOW_REGISTER(BC));
				PUT_BYTE(HL, acu);
				--HL;
				temp = HIGH_REGISTER(BC);
				BC -= 0x100;
				INOUTFLAGS_NONZERO((LOW_REGISTER(BC) - 1) & 0xff);
				break;

			case 0xab:      /* OUTD */
				acu = GET_BYTE(HL);
				cpu_out(LOW_REGISTER(BC), acu);
				--HL;
				temp = HIGH_REGISTER(BC);
				BC -= 0x100;
				INOUTFLAGS_NONZERO(LOW_REGISTER(HL));
				break;

			case 0xb0:      /* LDIR */
				BC &= ADDRMASK;
				if (BC == 0)
					BC = 0x10000;
				for (;;) {
					acu = RAM_PP(HL);
					PUT_BYTE_PP(DE, acu);
					if (--BC == 0)
						break;
					INCR(2); /* Repeat re-fetches ED B0 */
					steps++;
				}
				acu += HIGH_REGISTER(AF);
				AF = (AF & ~0x3e) | (acu & 8) | ((acu & 2) << 4);
				break;

			case 0xb1:      /* CPIR */
				acu = HIGH_REGISTER(AF);
				BC &= ADDRMASK;
				if (BC == 0)
					BC = 0x10000;
				for (;;) {
					temp = RAM_PP(HL);
					op = --BC != 0;
					sum = acu - temp;
					if (!(op && sum != 0))
						break;
					INCR(2); /* Repeat re-fetches ED B1 */
					steps++;
				}
				cbits = acu ^ temp ^ sum;
				AF = (AF & ~0xfe) | (sum & 0x80) | (!(sum & 0xff) << 6) |
					(((sum - ((cbits & 16) >> 4)) & 2) << 4) |
					(cbits & 16) | ((sum - ((cbits >> 4) & 1)) & 8) |
					op << 2 | 2;
				if ((sum & 15) == 8 && (cbits & 16) != 0)
					AF &= ~8;
				break;

			case 0xb2:      /* INIR */
				temp = HIGH_REGISTER(BC);
				if (temp == 0)
					temp = 0x100;
				for (;;) {
					acu = cpu_in(LOW_REGISTER(BC));
					PUT_BYTE(HL, acu);
					++HL;
					if (--temp == 0)
						break;
					INCR(2);
					steps++;
				}
				temp = HIGH_REGISTER(BC);
				SET_HIGH_REGISTER(BC, 0);
				INOUTFLAGS_ZERO((LOW_REGISTER(BC) + 1) & 0xff);
				break;

			case 0xb3:      /* OTIR */
				temp = HIGH_REGISTER(BC);
				if (temp == 0)
					temp = 0x100;
				for (;;) {
					acu = GET_BYTE(HL);
					cpu_out(LOW_REGISTER(BC), acu);
					++HL;
					if (--temp == 0)
						break;
					INCR(2);
					steps++;
				}
				temp = HIGH_REGISTER(BC);
				SET_HIGH_REGISTER(BC, 0);
				INOUTFLAGS_ZERO(LOW_REGISTER(HL));
				break;

			case 0xb8:      /* LDDR */
				BC &= ADDRMASK;
				if (BC == 0)
					BC = 0x10000;
				for (;;) {
					acu = RAM_MM(HL);
					PUT_BYTE_MM(DE, acu);
					if (--BC == 0)
						break;
					INCR(2); /* Repeat re-fetches ED B8 */
					steps++;
				}
				acu += HIGH_REGISTER(AF);
				AF = (AF & ~0x3e) | (acu & 8) | ((acu & 2) << 4);
				break;

			case 0xb9:      /* CPDR */
				acu = HIGH_REGISTER(AF);
				BC &= ADDRMASK;
				if (BC == 0)
					BC = 0x10000;
				for (;;) {
					temp = RAM_MM(HL);
					op = --BC != 0;
					sum = acu - temp;
					if (!(op && sum != 0))
						break;
					INCR(2); /* Repeat re-fetches ED B9 */
					steps++;
				}
				cbits = acu ^ temp ^ sum;
				AF = (AF & ~0xfe) | (sum & 0x80) | (!(sum & 0xff) << 6) |
					(((sum - ((cbits & 16) >> 4)) & 2) << 4) |
					(cbits & 16) | ((sum - ((cbits >> 4) & 1)) & 8) |
					op << 2 | 2;
				if ((sum & 15) == 8 && (cbits & 16) != 0)
					AF &= ~8;
				break;

			case 0xba:      /* INDR */
				temp = HIGH_REGISTER(BC);
				if (temp == 0)
					temp = 0x100;
				for (;;) {
					acu = cpu_in(LOW_REGISTER(BC));
					PUT_BYTE(HL, acu);
					--HL;
					if (--temp == 0)
						break;
					INCR(2);
					steps++;
				}
				temp = HIGH_REGISTER(BC);
				SET_HIGH_REGISTER(BC, 0);
				INOUTFLAGS_ZERO((LOW_REGISTER(BC) - 1) & 0xff);
				break;

			case 0xbb:      /* OTDR */
				temp = HIGH_REGISTER(BC);
				if (temp == 0)
					temp = 0x100;
				for (;;) {
					acu = GET_BYTE(HL);
					cpu_out(LOW_REGISTER(BC), acu);
					--HL;
					if (--temp == 0)
						break;
					INCR(2);
					steps++;
				}
				temp = HIGH_REGISTER(BC);
				SET_HIGH_REGISTER(BC, 0);
				INOUTFLAGS_ZERO(LOW_REGISTER(HL));
				break;

			default:    /* ignore ED and following byte */
				break;
			}
			break;

		case 0xee:      /* XOR nn */
			AF = xororTable[((AF >> 8) ^ RAM_PP(PC)) & 0xff];
			break;

		case 0xef:      /* RST 28H */
			PUSH(PC);
			PC = 0x28;
			break;

		case 0xf0:      /* RET P */
			if (!(TSTFLAG(S)))
				POP(PC);
			break;

		case 0xf1:      /* POP AF */
			POP(AF);
			break;

		case 0xf2:      /* JP P,nnnn */
			JPC(!TSTFLAG(S));
			break;

		case 0xf3:      /* DI */
			IFF = 0;
			break;

		case 0xf4:      /* CALL P,nnnn */
			CALLC(!TSTFLAG(S));
			break;

		case 0xf5:      /* PUSH AF */
			PUSH(AF);
			break;

		case 0xf6:      /* OR nn */
			AF = xororTable[((AF >> 8) | RAM_PP(PC)) & 0xff];
			break;

		case 0xf7:      /* RST 30H */
			PUSH(PC);
			PC = 0x30;
			break;

		case 0xf8:      /* RET M */
			if (TSTFLAG(S))
				POP(PC);
			break;

		case 0xf9:      /* LD SP,HL */
			SP = HL;
			break;

		case 0xfa:      /* JP M,nnnn */
			JPC(TSTFLAG(S));
			break;

		case 0xfb:      /* EI */
			IFF = 3;
			break;

		case 0xfc:      /* CALL M,nnnn */
			CALLC(TSTFLAG(S));
			break;

		case 0xfd:      /* FD prefix */
			INCR(1); /* Add one M1 cycle to refresh counter */
			switch (RAM_PP(PC)) {

			case 0x09:      /* ADD IY,BC */
				IY &= ADDRMASK;
				BC &= ADDRMASK;
				sum = IY + BC;
				AF = (AF & ~0x3b) | ((sum >> 8) & 0x28) | cbitsTable[(IY ^ BC ^ sum) >> 8];
				IY = sum;
				break;

			case 0x19:      /* ADD IY,DE */
				IY &= ADDRMASK;
				DE &= ADDRMASK;
				sum = IY + DE;
				AF = (AF & ~0x3b) | ((sum >> 8) & 0x28) | cbitsTable[(IY ^ DE ^ sum) >> 8];
				IY = sum;
				break;

			case 0x21:      /* LD IY,nnnn */
				IY = GET_WORD(PC++);
				++PC;
				break;

			case 0x22:      /* LD (nnnn),IY */
				temp = GET_WORD(PC++);
				PUT_WORD(temp, IY);
				++PC;
				break;

			case 0x23:      /* INC IY */
				++IY;
				break;

			case 0x24:      /* INC IYH */
				IY += 0x100;
				AF = (AF & ~0xfe) | incZ80Table[HIGH_REGISTER(IY)];
				break;

			case 0x25:      /* DEC IYH */
				IY -= 0x100;
				AF = (AF & ~0xfe) | decZ80Table[HIGH_REGISTER(IY)];
				break;

			case 0x26:      /* LD IYH,nn */
				SET_HIGH_REGISTER(IY, RAM_PP(PC));
				break;

			case 0x29:      /* ADD IY,IY */
				IY &= ADDRMASK;
				sum = IY + IY;
				AF = (AF & ~0x3b) | cbitsDup16Table[sum >> 8];
				IY = sum;
				break;

			case 0x2a:      /* LD IY,(nnnn) */
				IY = GET_WORD(GET_WORD(PC++));
				++PC;
				break;

			case 0x2b:      /* DEC IY */
				--IY;
				break;

			case 0x2c:      /* INC IYL */
				temp = LOW_REGISTER(IY) + 1;
				SET_LOW_REGISTER(IY, temp);
				AF = (AF & ~0xfe) | incZ80Table[temp];
				break;

			case 0x2d:      /* DEC IYL */
				temp = LOW_REGISTER(IY) - 1;
				SET_LOW_REGISTER(IY, temp);
				AF = (AF & ~0xfe) | decZ80Table[temp & 0xff];
				break;

			case 0x2e:      /* LD IYL,nn */
				SET_LOW_REGISTER(IY, RAM_PP(PC));
				break;

			case 0x34:      /* INC (IY+dd) */
				adr = IY + (int8)RAM_PP(PC);
				temp = GET_BYTE(adr) + 1;
				PUT_BYTE(adr, temp);
				AF = (AF & ~0xfe) | incZ80Table[temp];
				break;

			case 0x35:      /* DEC (IY+dd) */
				adr = IY + (int8)RAM_PP(PC);
				temp = GET_BYTE(adr) - 1;
				PUT_BYTE(adr, temp);
				AF = (AF & ~0xfe) | decZ80Table[temp & 0xff];
				break;

			case 0x36:      /* LD (IY+dd),nn */
				adr = IY + (int8)RAM_PP(PC);
				PUT_BYTE(adr, RAM_PP(PC));
				break;

			case 0x39:      /* ADD IY,SP */
				IY &= ADDRMASK;
				SP &= ADDRMASK;
				sum = IY + SP;
				AF = (AF & ~0x3b) | ((sum >> 8) & 0x28) | cbitsTable[(IY ^ SP ^ sum) >> 8];
				IY = sum;
				break;

			case 0x44:      /* LD B,IYH */
				SET_HIGH_REGISTER(BC, HIGH_REGISTER(IY));
				break;

			case 0x45:      /* LD B,IYL */
				SET_HIGH_REGISTER(BC, LOW_REGISTER(IY));
				break;

			case 0x46:      /* LD B,(IY+dd) */
				SET_HIGH_REGISTER(BC, GET_BYTE(IY + (int8)RAM_PP(PC)));
				break;

			case 0x4c:      /* LD C,IYH */
				SET_LOW_REGISTER(BC, HIGH_REGISTER(IY));
				break;

			case 0x4d:      /* LD C,IYL */
				SET_LOW_REGISTER(BC, LOW_REGISTER(IY));
				break;

			case 0x4e:      /* LD C,(IY+dd) */
				SET_LOW_REGISTER(BC, GET_BYTE(IY + (int8)RAM_PP(PC)));
				break;

			case 0x54:      /* LD D,IYH */
				SET_HIGH_REGISTER(DE, HIGH_REGISTER(IY));
				break;

			case 0x55:      /* LD D,IYL */
				SET_HIGH_REGISTER(DE, LOW_REGISTER(IY));
				break;

			case 0x56:      /* LD D,(IY+dd) */
				SET_HIGH_REGISTER(DE, GET_BYTE(IY + (int8)RAM_PP(PC)));
				break;

			case 0x5c:      /* LD E,IYH */
				SET_LOW_REGISTER(DE, HIGH_REGISTER(IY));
				break;

			case 0x5d:      /* LD E,IYL */
				SET_LOW_REGISTER(DE, LOW_REGISTER(IY));
				break;

			case 0x5e:      /* LD E,(IY+dd) */
				SET_LOW_REGISTER(DE, GET_BYTE(IY + (int8)RAM_PP(PC)));
				break;

			case 0x60:      /* LD IYH,B */
				SET_HIGH_REGISTER(IY, HIGH_REGISTER(BC));
				break;

			case 0x61:      /* LD IYH,C */
				SET_HIGH_REGISTER(IY, LOW_REGISTER(BC));
				break;

			case 0x62:      /* LD IYH,D */
				SET_HIGH_REGISTER(IY, HIGH_REGISTER(DE));
				break;

			case 0x63:      /* LD IYH,E */
				SET_HIGH_REGISTER(IY, LOW_REGISTER(DE));
				break;

			case 0x64:      /* LD IYH,IYH */
				break;

			case 0x65:      /* LD IYH,IYL */
				SET_HIGH_REGISTER(IY, LOW_REGISTER(IY));
				break;

			case 0x66:      /* LD H,(IY+dd) */
				SET_HIGH_REGISTER(HL, GET_BYTE(IY + (int8)RAM_PP(PC)));
				break;

			case 0x67:      /* LD IYH,A */
				SET_HIGH_REGISTER(IY, HIGH_REGISTER(AF));
				break;

			case 0x68:      /* LD IYL,B */
				SET_LOW_REGISTER(IY, HIGH_REGISTER(BC));
				break;

			case 0x69:      /* LD IYL,C */
				SET_LOW_REGISTER(IY, LOW_REGISTER(BC));
				break;

			case 0x6a:      /* LD IYL,D */
				SET_LOW_REGISTER(IY, HIGH_REGISTER(DE));
				break;

			case 0x6b:      /* LD IYL,E */
				SET_LOW_REGISTER(IY, LOW_REGISTER(DE));
				break;

			case 0x6c:      /* LD IYL,IYH */
				SET_LOW_REGISTER(IY, HIGH_REGISTER(IY));
				break;

			case 0x6d:      /* LD IYL,IYL */
				break;

			case 0x6e:      /* LD L,(IY+dd) */
				SET_LOW_REGISTER(HL, GET_BYTE(IY + (int8)RAM_PP(PC)));
				break;

			case 0x6f:      /* LD IYL,A */
				SET_LOW_REGISTER(IY, HIGH_REGISTER(AF));
				break;

			case 0x70:      /* LD (IY+dd),B */
				PUT_BYTE(IY + (int8)RAM_PP(PC), HIGH_REGISTER(BC));
				break;

			case 0x71:      /* LD (IY+dd),C */
				PUT_BYTE(IY + (int8)RAM_PP(PC), LOW_REGISTER(BC));
				break;

			case 0x72:      /* LD (IY+dd),D */
				PUT_BYTE(IY + (int8)RAM_PP(PC), HIGH_REGISTER(DE));
				break;

			case 0x73:      /* LD (IY+dd),E */
				PUT_BYTE(IY + (int8)RAM_PP(PC), LOW_REGISTER(DE));
				break;

			case 0x74:      /* LD (IY+dd),H */
				PUT_BYTE(IY + (int8)RAM_PP(PC), HIGH_REGISTER(HL));
				break;

			case 0x75:      /* LD (IY+dd),L */
				PUT_BYTE(IY + (int8)RAM_PP(PC), LOW_REGISTER(HL));
				break;

			case 0x77:      /* LD (IY+dd),A */
				PUT_BYTE(IY + (int8)RAM_PP(PC), HIGH_REGISTER(AF));
				break;

			case 0x7c:      /* LD A,IYH */
				SET_HIGH_REGISTER(AF, HIGH_REGISTER(IY));
				break;

			case 0x7d:      /* LD A,IYL */
				SET_HIGH_REGISTER(AF, LOW_REGISTER(IY));
				break;

			case 0x7e:      /* LD A,(IY+dd) */
				SET_HIGH_REGISTER(AF, GET_BYTE(IY + (int8)RAM_PP(PC)));
				break;

			case 0x84:      /* ADD A,IYH */
				temp = HIGH_REGISTER(IY);
				acu = HIGH_REGISTER(AF);
				sum = acu + temp;
				AF = addTable[sum] | cbitsZ80Table[acu ^ temp ^ sum];
				break;

			case 0x85:      /* ADD A,IYL */
				temp = LOW_REGISTER(IY);
				acu = HIGH_REGISTER(AF);
				sum = acu + temp;
				AF = addTable[sum] | cbitsZ80Table[acu ^ temp ^ sum];
				break;

			case 0x86:      /* ADD A,(IY+dd) */
				adr = IY + (int8)RAM_PP(PC);
				temp = GET_BYTE(adr);
				acu = HIGH_REGISTER(AF);
				sum = acu + temp;
				AF = addTable[sum] | cbitsZ80Table[acu ^ temp ^ sum];
				break;

			case 0x8c:      /* ADC A,IYH */
				temp = HIGH_REGISTER(IY);
				acu = HIGH_REGISTER(AF);
				sum = acu + temp + TSTFLAG(C);
				AF = addTable[sum] | cbitsZ80Table[acu ^ temp ^ sum];
				break;

			case 0x8d:      /* ADC A,IYL */
				temp = LOW_REGISTER(IY);
				acu = HIGH_REGISTER(AF);
				sum = acu + temp + TSTFLAG(C);
				AF = addTable[sum] | cbitsZ80Table[acu ^ temp ^ sum];
				break;

			case 0x8e:      /* ADC A,(IY+dd) */
				adr = IY + (int8)RAM_PP(PC);
				temp = GET_BYTE(adr);
				acu = HIGH_REGISTER(AF);
				sum = acu + temp + TSTFLAG(C);
				AF = addTable[sum] | cbitsZ80Table[acu ^ temp ^ sum];
				break;

			case 0x96:      /* SUB (IY+dd) */
				adr = IY + (int8)RAM_PP(PC);
				temp = GET_BYTE(adr);
				acu = HIGH_REGISTER(AF);
				sum = acu - temp;
				AF = addTable[sum & 0xff] | cbits2Z80Table[(acu ^ temp ^ sum) & 0x1ff];
				break;

			case 0x94:      /* SUB IYH */
				SETFLAG(C, 0);
				__attribute__((fallthrough));/* a bit less efficient but smaller code */

			case 0x9c:      /* SBC A,IYH */
				temp = HIGH_REGISTER(IY);
				acu = HIGH_REGISTER(AF);
				sum = acu - temp - TSTFLAG(C);
				AF = addTable[sum & 0xff] | cbits2Z80Table[(acu ^ temp ^ sum) & 0x1ff];
				break;

			case 0x95:      /* SUB IYL */
				SETFLAG(C, 0);
				__attribute__((fallthrough));/* a bit less efficient but smaller code */

			case 0x9d:      /* SBC A,IYL */
				temp = LOW_REGISTER(IY);
				acu = HIGH_REGISTER(AF);
				sum = acu - temp - TSTFLAG(C);
				AF = addTable[sum & 0xff] | cbits2Z80Table[(acu ^ temp ^ sum) & 0x1ff];
				break;

			case 0x9e:      /* SBC A,(IY+dd) */
				adr = IY + (int8)RAM_PP(PC);
				temp = GET_BYTE(adr);
				acu = HIGH_REGISTER(AF);
				sum = acu - temp - TSTFLAG(C);
				AF = addTable[sum & 0xff] | cbits2Z80Table[(acu ^ temp ^ sum) & 0x1ff];
				break;

			case 0xa4:      /* AND IYH */
				AF = andTable[((AF & IY) >> 8) & 0xff];
				break;

			case 0xa5:      /* AND IYL */
				AF = andTable[((AF >> 8)& IY) & 0xff];
				break;

			case 0xa6:      /* AND (IY+dd) */
				AF = andTable[((AF >> 8)& GET_BYTE(IY + (int8)RAM_PP(PC))) & 0xff];
				break;

			case 0xac:      /* XOR IYH */
				AF = xororTable[((AF ^ IY) >> 8) & 0xff];
				break;

			case 0xad:      /* XOR IYL */
				AF = xororTable[((AF >> 8) ^ IY) & 0xff];
				break;

			case 0xae:      /* XOR (IY+dd) */
				AF = xororTable[((AF >> 8) ^ GET_BYTE(IY + (int8)RAM_PP(PC))) & 0xff];
				break;

			case 0xb4:      /* OR IYH */
				AF = xororTable[((AF | IY) >> 8) & 0xff];
				break;

			case 0xb5:      /* OR IYL */
				AF = xororTable[((AF >> 8) | IY) & 0xff];
				break;

			case 0xb6:      /* OR (IY+dd) */
				AF = xororTable[((AF >> 8) | GET_BYTE(IY + (int8)RAM_PP(PC))) & 0xff];
				break;

			case 0xbc:      /* CP IYH */
				temp = HIGH_REGISTER(IY);
				AF = (AF & ~0x28) | (temp & 0x28);
				acu = HIGH_REGISTER(AF);
				sum = acu - temp;
				AF = (AF & ~0xff) | cpTable[sum & 0xff] | (temp & 0x28) |
					cbits2Z80Table[(acu ^ temp ^ sum) & 0x1ff];
				break;

			case 0xbd:      /* CP IYL */
				temp = LOW_REGISTER(IY);
				AF = (AF & ~0x28) | (temp & 0x28);
				acu = HIGH_REGISTER(AF);
				sum = acu - temp;
				AF = (AF & ~0xff) | cpTable[sum & 0xff] | (temp & 0x28) |
					cbits2Z80Table[(acu ^ temp ^ sum) & 0x1ff];
				break;

			case 0xbe:      /* CP (IY+dd) */
				adr = IY + (int8)RAM_PP(PC);
				temp = GET_BYTE(adr);
				AF = (AF & ~0x28) | (temp & 0x28);
				acu = HIGH_REGISTER(AF);
				sum = acu - temp;
				AF = (AF & ~0xff) | cpTable[sum & 0xff] | (temp & 0x28) |
					cbits2Z80Table[(acu ^ temp ^ sum) & 0x1ff];
				break;

			case 0xcb:      /* CB prefix */
				adr = IY + (int8)RAM_PP(PC);
				switch ((op = GET_BYTE(PC)) & 7) {

				case 0:
					acu = HIGH_REGISTER(BC);
					break;

				case 1:
					acu = LOW_REGISTER(BC);
					break;

				case 2:
					acu = HIGH_REGISTER(DE);
					break;

				case 3:
					acu = LOW_REGISTER(DE);
					break;

				case 4:
					acu = HIGH_REGISTER(HL);
					break;

				case 5:
					acu = LOW_REGISTER(HL);
					break;

				case 6:
					acu = GET_BYTE(adr);
					break;

				default:
					acu = HIGH_REGISTER(AF);
					break;
				}
				++PC;
				switch (op & 0xc0) {

				case 0x00:  /* shift/rotate */
					switch (op & 0x38) {

						case 0x00:/* RLC */
							temp = (acu << 1) | (acu >> 7);
							cbits = temp & 1;
							break;
	
						case 0x08:/* RRC */
							temp = (acu >> 1) | (acu << 7);
							cbits = temp & 0x80;
							break;
	
						case 0x10:/* RL */
							temp = (acu << 1) | TSTFLAG(C);
							cbits = acu & 0x80;
							break;
	
						case 0x18:/* RR */
							temp = (acu >> 1) | (TSTFLAG(C) << 7);
							cbits = acu & 1;
							break;
	
						case 0x20:/* SLA */
							temp = acu << 1;
							cbits = acu & 0x80;
							break;
	
						case 0x28:/* SRA */
							temp = (acu >> 1) | (acu & 0x80);
							cbits = acu & 1;
							break;
	
						case 0x30:/* SLIA */
							temp = (acu << 1) | 1;
							cbits = acu & 0x80;
							break;
	
						case 0x38:/* SRL */
							temp = acu >> 1;
							cbits = acu & 1;
							break;
	
						default:
							temp = acu;
							cbits = 0;
					}
					AF = (AF & ~0xff) | rotateShiftTable[temp & 0xff] | !!cbits;
					break;

				case 0x40:  /* BIT */
					if (acu & (1 << ((op >> 3) & 7)))
						AF = (AF & ~0xfe) | 0x10 | (((op & 0x38) == 0x38) << 7);
					else
						AF = (AF & ~0xfe) | 0x54;
					if ((op & 7) != 6)
						AF |= (acu & 0x28);
					temp = acu;
					break;

				case 0x80:  /* RES */
					temp = acu & ~(1 << ((op >> 3) & 7));
					break;

				case 0xc0:  /* SET */
					temp = acu | (1 << ((op >> 3) & 7));
					break;
				}
				switch (op & 7) {

				case 0:
					SET_HIGH_REGISTER(BC, temp);
					break;

				case 1:
					SET_LOW_REGISTER(BC, temp);
					break;

				case 2:
					SET_HIGH_REGISTER(DE, temp);
					break;

				case 3:
					SET_LOW_REGISTER(DE, temp);
					break;

				case 4:
					SET_HIGH_REGISTER(HL, temp);
					break;

				case 5:
					SET_LOW_REGISTER(HL, temp);
					break;

				case 6:
					PUT_BYTE(adr, temp);
					break;

				default:
					SET_HIGH_REGISTER(AF, temp);
					break;
				}
				break;

			case 0xe1:      /* POP IY */
				POP(IY);
				break;

			case 0xe3:      /* EX (SP),IY */
				temp = IY;
				POP(IY);
				PUSH(temp);
				break;

			case 0xe5:      /* PUSH IY */
				PUSH(IY);
				break;

			case 0xe9:      /* JP (IY) */
				PC = IY;
				break;

			case 0xf9:      /* LD SP,IY */
				SP = IY;
				break;

			default:            /* ignore FD */
				PC = (PC - 1) & 0xffff;
			}
			break;

		case 0xfe:      /* CP nn */
			temp = RAM_PP(PC);
			AF = (AF & ~0x28) | (temp & 0x28);
			acu = HIGH_REGISTER(AF);
			sum = acu - temp;
			cbits = acu ^ temp ^ sum;
			AF = (AF & ~0xff) | cpTable[sum & 0xff] | (temp & 0x28) |
				(SET_PV) | cbits2Table[cbits & 0x1ff];
			break;

		case 0xff:      /* RST 38H */
			PUSH(PC);
			PC = 0x38;
		}

    vm->af = AF & 0xffffU;
    vm->bc = BC & 0xffffU;
    vm->de = DE & 0xffffU;
    vm->hl = HL & 0xffffU;
    vm->ix = IX & 0xffffU;
    vm->iy = IY & 0xffffU;
    vm->pc = PC & 0xffffU;
    vm->sp = SP & 0xffffU;
    vm->af1 = AF1 & 0xffffU;
    vm->bc1 = BC1 & 0xffffU;
    vm->de1 = DE1 & 0xffffU;
    vm->hl1 = HL1 & 0xffffU;
    vm->iff = IFF & 0xffU;
    vm->ir = IR & 0xffffU;
    vm->total_steps += steps;
    return steps;
}

CpmStatus z80_run(CpmVm *vm, uint64_t max_steps) {
    uint64_t ran = 0;
    z80_init_tables();
    while (vm->status == CPM_RUNNING) {
        if (vm->stop_flag && *vm->stop_flag) {
            vm->status = CPM_EXITED;
            vm->exit_code = 130;
            snprintf(vm->exit_reason, sizeof(vm->exit_reason), "signal");
            break;
        }
        if (max_steps > 0 && ran >= max_steps) {
            vm->status = CPM_STEP_LIMIT;
            break;
        }
        if (ran > 0 && vm->num_breakpoints > 0) {
            size_t bi;
            for (bi = 0; bi < vm->num_breakpoints; bi++) {
                if (vm->pc == vm->breakpoints[bi]) {
                    vm->status = CPM_BREAKPOINT;
                    return vm->status;
                }
            }
        }
        ran += z80_exec_one(vm);
    }
    return vm->status;
}
