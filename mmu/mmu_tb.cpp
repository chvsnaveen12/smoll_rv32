// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Naveen Chavali


#include "Vmmu_tb.h"
#include "Vmmu_tb___024root.h"
#include "Vmmu_tb_core_fsm.h"
#include "Vmmu_tb_mmu.h"
#include "Vmmu_tb_mmu_tb.h"
#include <verilated.h>
#include <verilated_vcd_c.h>

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── Simulation time ─────────────────────────────────────────────── */
static vluint64_t main_time = 0;
double sc_time_stamp(void) {
    return main_time;
}

/* ── Tunables ────────────────────────────────────────────────────── */
#define REQ_READY_LATENCY 0
#define RESP_VALID_LATENCY 1
// #define MAX_CYCLES          387000000
#define MAX_CYCLES 3870000000

// #define START_CYCLE         0xFFFFFFFFFFFFFFFFULL  /* VCD disabled — text logs only */
#define START_CYCLE (MAX_CYCLES - 5000000) /* VCD disabled — text logs only */

/* ── Debug ───────────────────────────────────────────────────────── */
#define STALL_THRESHOLD 200000000   /* cycles without UART → stall */
#define STALL_LOG_INTERVAL 50000000 /* print debug every N cycles when stalled */

/* ── PC history for crash debugging ─────────────────────────────── */
#define PC_HIST_SIZE 4096

typedef struct {
    uint64_t cycle;
    uint32_t pc;
    uint32_t core_st;
    uint32_t mmu_st;
    uint32_t bus_addr;
    uint32_t instr;
    uint32_t next_state;
    uint32_t ra;
} pc_hist_entry_t;

static pc_hist_entry_t pc_hist[PC_HIST_SIZE];
static int pc_hist_idx = 0;
static int pc_zero_caught = 0;
static int bus_fault_caught = 0;
static int prologue_seen = 0;
static int prologue_count = 0;
static int epilogue_count = 0;
static uint64_t fetch_count = 0;
static uint32_t prev_core_st = 0;

/* ── Memory map ──────────────────────────────────────────────────── */
#define BOOTROM_BASE 0x40000000U
#define BOOTROM_SIZE 256 /* bytes — plenty for the rom */

#define RAM_BASE 0x80000000U
#define RAM_SIZE (128U * 1024 * 1024) /* 128 MiB */

/* UART registers (no backing memory, handled directly) */
#define UART_RX_DATA 0x10000000U
#define UART_RX_IRQ 0x10000004U
#define UART_TX_DATA 0x10000008U
#define UART_TX_BUSY 0x1000000CU
#define UART_TX_READ 0x100000C8U

/* CLINT */
#define CLINT_BASE 0x20000000U
#define CLINT_SIZE 0x000C0000U

/* PLIC */
#define PLIC_BASE 0x30000000U
#define PLIC_SIZE 0x03FFF004U

static uint8_t bootrom[BOOTROM_SIZE];
static uint8_t *ram;

/* ── CLINT (from rv32_emu) ───────────────────────────────────────── */
typedef struct clint {
    uint32_t msip;
    uint64_t mtimecmp;
    uint64_t mtime;
    uint64_t cycle;
} clint_td;

static clint_td clint;

#define MSIP_OFFSET 0x0
#define MSIP_SIZE 0x04
#define MTIME_CMP_OFFSET 0x4000
#define MTIME_CMP_SIZE 0x08
#define MTIME_OFFSET 0xBFF8
#define MTIME_SIZE 0x08

static uint32_t clint_read32(uint32_t offset) {
    uint32_t val = 0;
    uint8_t *src = NULL;
    uint32_t off = 0;

    if (offset >= MSIP_OFFSET && offset + 4 <= MSIP_OFFSET + MSIP_SIZE) {
        src = (uint8_t *)&clint.msip;
        off = offset - MSIP_OFFSET;
    } else if (offset >= MTIME_CMP_OFFSET && offset + 4 <= MTIME_CMP_OFFSET + MTIME_CMP_SIZE) {
        src = (uint8_t *)&clint.mtimecmp;
        off = offset - MTIME_CMP_OFFSET;
    } else if (offset >= MTIME_OFFSET && offset + 4 <= MTIME_OFFSET + MTIME_SIZE) {
        src = (uint8_t *)&clint.mtime;
        off = offset - MTIME_OFFSET;
    }

    if (src)
        memcpy(&val, &src[off], 4);
    return val;
}

static void clint_write32(uint32_t offset, uint32_t val) {
    uint8_t *dst = NULL;
    uint32_t off = 0;

    if (offset >= MSIP_OFFSET && offset + 4 <= MSIP_OFFSET + MSIP_SIZE) {
        dst = (uint8_t *)&clint.msip;
        off = offset - MSIP_OFFSET;
    } else if (offset >= MTIME_CMP_OFFSET && offset + 4 <= MTIME_CMP_OFFSET + MTIME_CMP_SIZE) {
        dst = (uint8_t *)&clint.mtimecmp;
        off = offset - MTIME_CMP_OFFSET;
    } else if (offset >= MTIME_OFFSET && offset + 4 <= MTIME_OFFSET + MTIME_SIZE) {
        dst = (uint8_t *)&clint.mtime;
        off = offset - MTIME_OFFSET;
    }

    if (dst)
        memcpy(&dst[off], &val, 4);
}

static void clint_update(bool *msi, bool *mti) {
    if (clint.cycle++ % 10000 == 0)
        clint.mtime++;

    *mti = clint.mtime >= clint.mtimecmp;
    *msi = clint.msip & 0x01;
}

/* ── PLIC (from rv32_emu) ────────────────────────────────────────── */
#define PLIC_PENDING_REGS 1
#define PLIC_PRIO_REGS 32
#define PLIC_ENABLE_REGS 1
#define PLIC_CLAIMED_REGS 1

typedef struct plic {
    uint32_t pending[PLIC_PENDING_REGS];
    uint32_t priority[PLIC_PRIO_REGS];
    uint32_t enable0[PLIC_ENABLE_REGS];
    uint32_t enable1[PLIC_ENABLE_REGS];
    uint32_t claim_complete0;
    uint32_t threshold0;
    uint32_t claim_complete1;
    uint32_t threshold1;
    uint32_t claimed[PLIC_CLAIMED_REGS];
} plic_td;

static plic_td plic;

/* PLIC register offsets (word-addressed internally) */
#define PLIC_PRIO_OFF (0x0 >> 2)
#define PLIC_PRIO_SZ (0x400 >> 2)
#define PLIC_PENDING_OFF (0x1000 >> 2)
#define PLIC_PENDING_SZ (0x20 >> 2)
#define PLIC_ENABLE0_OFF (0x2000 >> 2)
#define PLIC_ENABLE0_SZ (0x20 >> 2)
#define PLIC_ENABLE1_OFF (0x2080 >> 2)
#define PLIC_ENABLE1_SZ PLIC_ENABLE0_SZ
#define PLIC_PRIO0_THRESH_OFF (0x200000 >> 2)
#define PLIC_PRIO0_THRESH_SZ (0x04 >> 2)
#define PLIC_PRIO1_THRESH_OFF (0x201000 >> 2)
#define PLIC_PRIO1_THRESH_SZ (0x04 >> 2)
#define PLIC_CLAIM0_OFF (0x200004 >> 2)
#define PLIC_CLAIM0_SZ (0x04 >> 2)
#define PLIC_CLAIM1_OFF (0x201004 >> 2)
#define PLIC_CLAIM1_SZ PLIC_CLAIM0_SZ

static uint32_t plic_read32(uint32_t offset) {
    uint32_t addr = offset >> 2;
    uint32_t val = 0;

    if (addr >= PLIC_PRIO_OFF && addr < PLIC_PRIO_OFF + PLIC_PRIO_SZ)
        val = plic.priority[addr - PLIC_PRIO_OFF];
    else if (addr >= PLIC_PENDING_OFF && addr < PLIC_PENDING_OFF + PLIC_PENDING_SZ)
        val = plic.pending[addr - PLIC_PENDING_OFF];
    else if (addr >= PLIC_ENABLE0_OFF && addr < PLIC_ENABLE0_OFF + PLIC_ENABLE0_SZ)
        val = plic.enable0[addr - PLIC_ENABLE0_OFF];
    else if (addr >= PLIC_ENABLE1_OFF && addr < PLIC_ENABLE1_OFF + PLIC_ENABLE1_SZ)
        val = plic.enable1[addr - PLIC_ENABLE1_OFF];
    else if (addr >= PLIC_PRIO0_THRESH_OFF && addr < PLIC_PRIO0_THRESH_OFF + PLIC_PRIO0_THRESH_SZ)
        val = plic.threshold0;
    else if (addr >= PLIC_PRIO1_THRESH_OFF && addr < PLIC_PRIO1_THRESH_OFF + PLIC_PRIO1_THRESH_SZ)
        val = plic.threshold1;
    else if (addr >= PLIC_CLAIM0_OFF && addr < PLIC_CLAIM0_OFF + PLIC_CLAIM0_SZ) {
        val = plic.claim_complete0;
        uint32_t reg = val / 32;
        uint32_t bit = val % 32;
        plic.claimed[reg] |= 1 << bit;
    } else if (addr >= PLIC_CLAIM1_OFF && addr < PLIC_CLAIM1_OFF + PLIC_CLAIM1_SZ) {
        val = plic.claim_complete1;
        uint32_t reg = val / 32;
        uint32_t bit = val % 32;
        plic.claimed[reg] |= 1 << bit;
    }

    return val;
}

static void plic_write32(uint32_t offset, uint32_t val) {
    uint32_t addr = offset >> 2;

    if (addr >= PLIC_PRIO_OFF && addr < PLIC_PRIO_OFF + PLIC_PRIO_SZ)
        plic.priority[addr - PLIC_PRIO_OFF] = val & 0x07;
    else if (addr >= PLIC_PENDING_OFF && addr < PLIC_PENDING_OFF + PLIC_PENDING_SZ)
        plic.pending[addr - PLIC_PENDING_OFF] = val;
    else if (addr >= PLIC_ENABLE0_OFF && addr < PLIC_ENABLE0_OFF + PLIC_ENABLE0_SZ)
        plic.enable0[addr - PLIC_ENABLE0_OFF] = val;
    else if (addr >= PLIC_ENABLE1_OFF && addr < PLIC_ENABLE1_OFF + PLIC_ENABLE1_SZ)
        plic.enable1[addr - PLIC_ENABLE1_OFF] = val;
    else if (addr >= PLIC_PRIO0_THRESH_OFF && addr < PLIC_PRIO0_THRESH_OFF + PLIC_PRIO0_THRESH_SZ)
        plic.threshold0 = val & 0x07;
    else if (addr >= PLIC_PRIO1_THRESH_OFF && addr < PLIC_PRIO1_THRESH_OFF + PLIC_PRIO1_THRESH_SZ)
        plic.threshold1 = val & 0x07;
    else if (addr >= PLIC_CLAIM0_OFF && addr < PLIC_CLAIM0_OFF + PLIC_CLAIM0_SZ) {
        uint32_t reg = val / 32;
        uint32_t bit = val % 32;
        plic.claimed[reg] &= ~(1 << bit);
    } else if (addr >= PLIC_CLAIM1_OFF && addr < PLIC_CLAIM1_OFF + PLIC_CLAIM1_SZ) {
        uint32_t reg = val / 32;
        uint32_t bit = val % 32;
        plic.claimed[reg] &= ~(1 << bit);
    }
}

static void plic_update(bool *mei, bool *sei) {
    uint32_t irq_id0 = 0, irq_prio0 = 0;
    uint32_t irq_id1 = 0, irq_prio1 = 0;

    for (uint32_t i = 0; i < PLIC_ENABLE_REGS; i++) {
        if (!plic.enable0[i] || !plic.pending[i])
            continue;
        for (uint32_t j = 0; j < 32; j++) {
            if ((plic.enable0[i] & (1 << j)) && (plic.pending[i] & (1 << j)) &&
                (plic.priority[(i * 32) + j] >= plic.threshold0)) {
                if (plic.priority[(i * 32) + j] > irq_prio0) {
                    irq_prio0 = plic.priority[(i * 32) + j];
                    irq_id0 = (i * 32) + j;
                }
            }
        }
    }

    for (uint32_t i = 0; i < PLIC_ENABLE_REGS; i++) {
        if (!plic.enable1[i] || !plic.pending[i])
            continue;
        for (uint32_t j = 0; j < 32; j++) {
            if ((plic.enable1[i] & (1 << j)) && (plic.pending[i] & (1 << j)) &&
                (plic.priority[(i * 32) + j] >= plic.threshold1)) {
                if (plic.priority[(i * 32) + j] > irq_prio1) {
                    irq_prio1 = plic.priority[(i * 32) + j];
                    irq_id1 = (i * 32) + j;
                }
            }
        }
    }

    if (irq_prio0 > 0) {
        plic.claim_complete0 = irq_id0;
        *mei = true;
    } else {
        plic.claim_complete0 = 0;
        *mei = false;
    }

    if (irq_prio1 > 0) {
        plic.claim_complete1 = irq_id1;
        *sei = true;
    } else {
        plic.claim_complete1 = 0;
        *sei = false;
    }
}

/* ── Memory helpers ──────────────────────────────────────────────── */
static uint64_t g_cycles = 0; /* set from main loop for diagnostics */

static uint32_t mem_read32(uint32_t addr) {
    uint32_t val = 0;
    if (addr >= RAM_BASE && addr < RAM_BASE + RAM_SIZE)
        memcpy(&val, &ram[addr - RAM_BASE], 4);
    else if (addr >= BOOTROM_BASE && addr < BOOTROM_BASE + BOOTROM_SIZE)
        memcpy(&val, &bootrom[addr - BOOTROM_BASE], 4);
    else if (addr >= CLINT_BASE && addr < CLINT_BASE + CLINT_SIZE)
        val = clint_read32(addr - CLINT_BASE);
    else if (addr >= PLIC_BASE && addr < PLIC_BASE + PLIC_SIZE)
        val = plic_read32(addr - PLIC_BASE);
    else {
        fprintf(stderr, "\n!!! BUS FAULT [%lu]: READ from unmapped PA 0x%08x !!!\n", g_cycles,
                addr);
        fflush(stderr);
    }
    return val;
}

static void mem_write(uint32_t addr, uint32_t data, uint32_t wstrb) {
    uint8_t *dst = NULL;

    if (addr >= RAM_BASE && addr < RAM_BASE + RAM_SIZE)
        dst = &ram[addr - RAM_BASE];
    else if (addr >= BOOTROM_BASE && addr < BOOTROM_BASE + BOOTROM_SIZE)
        dst = &bootrom[addr - BOOTROM_BASE];
    else if (addr >= CLINT_BASE && addr < CLINT_BASE + CLINT_SIZE) {
        clint_write32(addr - CLINT_BASE, data);
        return;
    } else if (addr >= PLIC_BASE && addr < PLIC_BASE + PLIC_SIZE) {
        plic_write32(addr - PLIC_BASE, data);
        return;
    } else {
        fprintf(stderr,
                "\n!!! BUS FAULT [%lu]: STORE to unmapped PA 0x%08x data=0x%08x wstrb=0x%x !!!\n",
                g_cycles, addr, data, wstrb);
        fflush(stderr);
        return;
    }

    if (wstrb & 1)
        dst[0] = (uint8_t)(data);
    if (wstrb & 2)
        dst[1] = (uint8_t)(data >> 8);
    if (wstrb & 4)
        dst[2] = (uint8_t)(data >> 16);
    if (wstrb & 8)
        dst[3] = (uint8_t)(data >> 24);
}

/* ── Core dump (matches emulator core_dump format) ───────────────── */
static void rtl_core_dump(Vmmu_tb *top, uint64_t fetch_cnt) {
    auto *c = top->rootp->mmu_tb->core_inst;
    auto *csr =
        &top->rootp->mmu_tb->core_inst->__PVT__csrs__DOT__xstatus_q; /* just for the path prefix */
    (void)csr;

    uint32_t pc = c->pc_q;
    uint32_t instr = c->__PVT__fe_instr_q;

    // fprintf(stderr, "Cycle: %lu\n", fetch_cnt);
    fprintf(stderr, "Inst: 0x%08x\n", instr);
    fprintf(stderr, "PC: 0x%08x\n\n", pc);

    for (int i = 0; i < 16; i++)
        fprintf(stderr, "x%02d:0x%08x\t\tx%02d:0x%08x\n", i, c->__PVT__regs__DOT__registers[i],
                i + 16, c->__PVT__regs__DOT__registers[i + 16]);

    fprintf(stderr, "MIE:\t0x%08x\t\tMIP:\t0x%08x\n", c->__PVT__csrs__DOT__mie_q,
            c->__PVT__csrs__DOT__mip_q);
    fprintf(stderr, "MIDELEG:0x%08x\t\tMEDELEG:0x%08x\n", c->__PVT__csrs__DOT__mideleg_q,
            c->__PVT__csrs__DOT__medeleg_q);
    fprintf(stderr, "MTVEC:\t0x%08x\t\tMEPC:\t0x%08x\n", c->__PVT__csrs__DOT__mtvec_q,
            c->__PVT__csrs__DOT__mepc_q);
    fprintf(stderr, "MCAUSE:\t0x%08x\t\tMTVAL:\t0x%08x\n", c->__PVT__csrs__DOT__mcause_q,
            c->__PVT__csrs__DOT__mtval_q);
    fprintf(stderr, "SEPC:\t0x%08x\t\tSCAUSE:\t0x%08x\n", c->__PVT__csrs__DOT__sepc_q,
            c->__PVT__csrs__DOT__scause_q);
    fprintf(stderr, "STVEC:\t0x%08x\t\tSTVAL:\t0x%08x\n", c->__PVT__csrs__DOT__stvec_q,
            c->__PVT__csrs__DOT__stval_q);
    fprintf(stderr, "MSTATUS:0x%08x\t\tSATP:\t0x%08x\n", c->__PVT__csrs__DOT__xstatus_q,
            c->__PVT__csrs__DOT__satp_q);
    fprintf(stderr, "MSCRAT:0x%08x\t\tSSCRAT:\t0x%08x\n", c->__PVT__csrs__DOT__mscratch_q,
            c->__PVT__csrs__DOT__sscratch_q);
    fprintf(stderr, "PRIV:\t%u\n\n", c->__PVT__csrs__DOT__priv_q);

    fflush(stderr);
}

/* ── State dump helper ───────────────────────────────────────────── */
static void dump_state(const char *reason, Vmmu_tb *top, uint64_t cycles, uint32_t last_addr) {
    uint32_t pc = top->rootp->mmu_tb->core_inst->pc_q;
    uint32_t core_st = top->rootp->mmu_tb->core_inst->state_q;
    uint32_t next_st = top->rootp->mmu_tb->core_inst->next_state;
    uint32_t mmu_st = top->rootp->mmu_tb->mmu0->state_q;
    uint32_t instr = top->rootp->mmu_tb->core_inst->__PVT__fe_instr_q;

    fprintf(stderr, "\n=== %s at cycle %lu ===\n", reason, cycles);
    fprintf(stderr, "pc=0x%08x core_st=%u next_st=%u mmu_st=%u bus_addr=0x%08x\n", pc, core_st,
            next_st, mmu_st, last_addr);
    fprintf(stderr, "fe_instr=0x%08x\n", instr);

    /* Register file */
    fprintf(stderr, "\n--- Register file ---\n");
    for (int i = 0; i < 32; i++) {
        uint32_t rv = top->rootp->mmu_tb->core_inst->__PVT__regs__DOT__registers[i];
        fprintf(stderr, "  x%-2d = 0x%08x", i, rv);
        if ((i & 3) == 3)
            fprintf(stderr, "\n");
    }

    /* PC history */
    int total = pc_hist_idx < PC_HIST_SIZE ? pc_hist_idx : PC_HIST_SIZE;
    int start = pc_hist_idx < PC_HIST_SIZE ? 0 : pc_hist_idx % PC_HIST_SIZE;
    fprintf(stderr, "\n--- PC history (last %d committed) ---\n", total);
    for (int i = 0; i < total; i++) {
        pc_hist_entry_t *e = &pc_hist[(start + i) % PC_HIST_SIZE];
        fprintf(stderr, "  [%lu] pc=0x%08x st=%u next=%u instr=0x%08x bus=0x%08x ra=0x%08x\n",
                e->cycle, e->pc, e->core_st, e->next_state, e->instr, e->bus_addr, e->ra);
    }

    /* CSR state */
    fprintf(stderr, "\n--- CSR state ---\n");
    fprintf(stderr, "  priv    = %u\n", top->rootp->mmu_tb->core_inst->__PVT__csrs__DOT__priv_q);
    fprintf(stderr, "  mstatus = 0x%08x\n",
            top->rootp->mmu_tb->core_inst->__PVT__csrs__DOT__xstatus_q);
    fprintf(stderr, "  mepc    = 0x%08x\n",
            top->rootp->mmu_tb->core_inst->__PVT__csrs__DOT__mepc_q);
    fprintf(stderr, "  sepc    = 0x%08x\n",
            top->rootp->mmu_tb->core_inst->__PVT__csrs__DOT__sepc_q);
    fprintf(stderr, "  mcause  = 0x%08x\n",
            top->rootp->mmu_tb->core_inst->__PVT__csrs__DOT__mcause_q);
    fprintf(stderr, "  scause  = 0x%08x\n",
            top->rootp->mmu_tb->core_inst->__PVT__csrs__DOT__scause_q);
    fprintf(stderr, "  mtvec   = 0x%08x\n",
            top->rootp->mmu_tb->core_inst->__PVT__csrs__DOT__mtvec_q);
    fprintf(stderr, "  stvec   = 0x%08x\n",
            top->rootp->mmu_tb->core_inst->__PVT__csrs__DOT__stvec_q);
    fprintf(stderr, "  satp    = 0x%08x\n",
            top->rootp->mmu_tb->core_inst->__PVT__csrs__DOT__satp_q);
    fprintf(stderr, "  mip     = 0x%08x\n", top->rootp->mmu_tb->core_inst->__PVT__csrs__DOT__mip_q);
    fprintf(stderr, "  mie     = 0x%08x\n", top->rootp->mmu_tb->core_inst->__PVT__csrs__DOT__mie_q);
    fprintf(stderr, "  medeleg = 0x%08x\n",
            top->rootp->mmu_tb->core_inst->__PVT__csrs__DOT__medeleg_q);
    fprintf(stderr, "  mideleg = 0x%08x\n",
            top->rootp->mmu_tb->core_inst->__PVT__csrs__DOT__mideleg_q);

    /* TLB state */
    auto dump_tlb = [](const char *name, const VlWide<3> &tlb) {
        uint32_t w0 = tlb[0], w1 = tlb[1], w2 = tlb[2];
        uint32_t megapage = w0 & 1;
        uint32_t ppn0 = (w0 >> 1) & 0x3FF;
        uint32_t ppn1 = (w0 >> 11) & 0xFFF;
        uint32_t vpn0 = ((w1 & 0x1) << 9) | ((w0 >> 23) & 0x1FF);
        uint32_t vpn1 = (w1 >> 1) & 0x3FF;
        uint32_t write_f = (w1 >> 11) & 1;
        uint32_t read_f = (w1 >> 12) & 1;
        uint32_t exec_f = (w1 >> 13) & 1;
        uint32_t user_f = (w1 >> 14) & 1;
        uint32_t valid = (w2 >> 15) & 1;
        fprintf(stderr,
                "  %s: valid=%u mega=%u vpn1=0x%03x vpn0=0x%03x ppn1=0x%03x ppn0=0x%03x "
                "RWXU=%u%u%u%u\n",
                name, valid, megapage, vpn1, vpn0, ppn1, ppn0, read_f, write_f, exec_f, user_f);
        fprintf(stderr, "        raw: [0]=0x%08x [1]=0x%08x [2]=0x%08x\n", w0, w1, w2);
    };
    fprintf(stderr, "\n--- MMU TLB state ---\n");
    dump_tlb("ITLB", top->rootp->mmu_tb->mmu0->__PVT__itlb_q);
    dump_tlb("DTLB", top->rootp->mmu_tb->mmu0->__PVT__dtlb_q);

    /* L1 page table */
    uint32_t satp_val = top->rootp->mmu_tb->core_inst->__PVT__csrs__DOT__satp_q;
    uint32_t satp_ppn20 = satp_val & 0xFFFFF;
    uint32_t pt_base = satp_ppn20 << 12;
    fprintf(stderr, "\n--- L1 page table (satp=0x%08x, base PA=0x%08x) ---\n", satp_val, pt_base);
    for (int vpn1_i = 0x2FE; vpn1_i <= 0x30A; vpn1_i++) {
        uint32_t l1_addr = pt_base + vpn1_i * 4;
        uint32_t pte = mem_read32(l1_addr);
        uint32_t pte_ppn1 = (pte >> 20) & 0xFFF;
        uint32_t pte_ppn0 = (pte >> 10) & 0x3FF;
        uint32_t pte_rwxv = pte & 0xF;
        fprintf(stderr,
                "  VPN1=0x%03x @ PA 0x%08x: PTE=0x%08x ppn1=0x%03x ppn0=0x%03x flags=0x%03x %s\n",
                vpn1_i, l1_addr, pte, pte_ppn1, pte_ppn0, pte & 0x3FF,
                (pte_rwxv & 1) ? ((pte_rwxv & 0xE) ? "LEAF" : "PTR") : "INVALID");
    }

    fprintf(stderr, "\n");
    fflush(stderr);
}

/* ── Binary loader ───────────────────────────────────────────────── */
static void load_binary(const char *path, uint32_t base) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "Error: cannot open %s\n", path);
        exit(1);
    }

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t *dst = NULL;
    long cap = 0;

    if (base >= RAM_BASE && base < RAM_BASE + RAM_SIZE) {
        dst = &ram[base - RAM_BASE];
        cap = RAM_SIZE - (base - RAM_BASE);
    } else if (base >= BOOTROM_BASE && base < BOOTROM_BASE + BOOTROM_SIZE) {
        dst = &bootrom[base - BOOTROM_BASE];
        cap = BOOTROM_SIZE - (base - BOOTROM_BASE);
    } else {
        fprintf(stderr, "Error: base 0x%08x not in any region\n", base);
        fclose(f);
        exit(1);
    }

    if (size > cap) {
        fprintf(stderr, "Error: %s (%ld bytes) overflows region at 0x%08x\n", path, size, base);
        fclose(f);
        exit(1);
    }

    if ((long)fread(dst, 1, size, f) != size) {
        fprintf(stderr, "Error: short read on %s\n", path);
        fclose(f);
        exit(1);
    }
    fclose(f);

    printf("Loaded %s (%ld bytes) at 0x%08x\n", path, size, base);
}

/* ── Bootrom init ────────────────────────────────────────────────── */
static void init_bootrom(void) {
    static const uint32_t rom[] = {
        0x00000297,             /* auipc  t0, %pcrel_hi(fw_dyn)       */
        0x02828613,             /* addi   a2, t0, %pcrel_lo(1b)        */
        0xf1402573,             /* csrr   a0, mhartid                  */
        0x0202a583,             /* lw     a1, 32(t0)                   */
        0x0182a283,             /* lw     t0, 24(t0)                   */
        0x00028067,             /* jr     t0                            */
        0x80000000,             /* start: .dword RAM_BASE              */
        0x00000000, 0x86000000, /* fdt_laddr: .dword FDT_ADDR          */
        0x00000000, 0x4942534f, /* fw_dyn: OSBI                        */
        0x00000002,             /* Version                             */
        0x80400000,             /* Next stage addr (LINUX_ADDR)        */
        0x00000001,             /* Next stage mode (Supervisor)        */
        0x00000000,             /* OpenSBI options                     */
        0x00000000,             /* Boot Hart                           */
    };
    memcpy(bootrom, rom, sizeof(rom));
    printf("Initialized bootrom at 0x%08x\n", BOOTROM_BASE);
}

/* ── Main ────────────────────────────────────────────────────────── */
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    if (argc < 4) {
        fprintf(stderr, "Usage: %s OPENSBI_BIN LINUX_IMG DTB_FILE\n", argv[0]);
        return 1;
    }

    /* Allocate flat RAM */
    ram = (uint8_t *)calloc(RAM_SIZE, 1);
    if (!ram) {
        fprintf(stderr, "Error: cannot allocate %u bytes for RAM\n", RAM_SIZE);
        return 1;
    }

    /* Load images */
    memset(bootrom, 0, sizeof(bootrom));
    init_bootrom();
    load_binary(argv[1], 0x80000000); /* OpenSBI */
    load_binary(argv[2], 0x80400000); /* Linux   */
    load_binary(argv[3], 0x86000000); /* DTB     */

    /* Zero-init peripherals */
    memset(&clint, 0, sizeof(clint));
    memset(&plic, 0, sizeof(plic));

    /* DUT + trace */
    Vmmu_tb *top = new Vmmu_tb;
    VerilatedVcdC *tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("core_sim.vcd");

    /* Initial signals */
    top->clk_i = 0;
    top->rst_ni = 0;
    top->req_ready_i = 0;
    top->resp_valid_i = 0;
    top->resp_value_i = 0;
    top->m_ext_irq_i = 0;
    top->m_timer_irq_i = 0;
    top->m_soft_irq_i = 0;
    top->s_ext_irq_i = 0;

    /* Reset pulse */
    for (int i = 0; i < 10; i++) {
        top->rst_ni = 0;
        top->clk_i = !top->clk_i;
        top->eval();
        tfp->dump(main_time++);
    }
    top->rst_ni = 1;
    top->eval();
    tfp->dump(main_time++);

    /* Bus transaction state */
    uint32_t last_addr = 0;
    uint32_t last_wstrb = 0;
    uint32_t last_wdata = 0;
    int ready_cnt = REQ_READY_LATENCY;
    int valid_cnt = 0;
    int processing = 0;
    uint64_t cycles = 0;

    /* Stall detection */
    uint64_t last_uart_cycle = 0;
    int stall_logged = 0;

    /* ── Simulation loop ─────────────────────────────────────────── */
    while (!Verilated::gotFinish() && cycles < MAX_CYCLES) {
        top->clk_i = !top->clk_i;

        if (!top->clk_i) { /* falling edge — drive all inputs */
            g_cycles = cycles;

            if (ready_cnt > 0)
                ready_cnt--;

            /* req_ready */
            if (!processing) {
                top->req_ready_i = (ready_cnt <= 0);
            } else {
                top->req_ready_i = 0;
            }

            /* capture request (read outputs from previous rising edge) */
            if (top->req_valid_o && top->req_ready_i) {
                processing = 1;
                last_addr = top->req_addr_o;
                last_wstrb = top->req_wstrb_o;
                last_wdata = top->req_value_o;
                valid_cnt = RESP_VALID_LATENCY;
                ready_cnt = REQ_READY_LATENCY;
            }

            /* drive response */
            if (processing) {
                if (valid_cnt > 0) {
                    valid_cnt--;
                    top->resp_valid_i = 0;
                } else {
                    top->resp_valid_i = 1;

                    if (last_wstrb) {
                        /* STORE */
                        if (last_addr == UART_TX_DATA) {
                            putchar((uint8_t)last_wdata);
                            fflush(stdout);
                            last_uart_cycle = cycles;
                            stall_logged = 0;
                        } else if (last_addr >= RAM_BASE && last_addr < RAM_BASE + RAM_SIZE) {
                            /* Monitor: ALL writes to ra save slot after first prologue seen */
                            if (last_addr == 0x82081acc && prologue_seen) {
                                uint32_t pc_now = top->rootp->mmu_tb->core_inst->pc_q;
                                uint32_t va_q = top->rootp->mmu_tb->mmu0->__PVT__req_addr_q;
                                fprintf(stderr,
                                        "[%lu] RA-SLOT WRITE: PA=0x%08x data=0x%08x wstrb=0x%x "
                                        "VA=0x%08x pc=0x%08x\n",
                                        cycles, last_addr, last_wdata, last_wstrb, va_q, pc_now);
                                fflush(stderr);
                            }
                            mem_write(last_addr, last_wdata, last_wstrb);
                        } else if (last_addr >= BOOTROM_BASE &&
                                   last_addr < BOOTROM_BASE + BOOTROM_SIZE) {
                            mem_write(last_addr, last_wdata, last_wstrb);
                        } else if (last_addr >= CLINT_BASE && last_addr < CLINT_BASE + CLINT_SIZE) {
                            clint_write32(last_addr - CLINT_BASE, last_wdata);
                        } else if (last_addr >= PLIC_BASE && last_addr < PLIC_BASE + PLIC_SIZE) {
                            plic_write32(last_addr - PLIC_BASE, last_wdata);
                        } else if (!bus_fault_caught) {
                            bus_fault_caught = 1;
                            fprintf(stderr,
                                    "\n!!! BUS FAULT: STORE to unmapped PA 0x%08x data=0x%08x "
                                    "wstrb=0x%x !!!\n",
                                    last_addr, last_wdata, last_wstrb);
                            dump_state("BUS FAULT (STORE to unmapped PA)", top, cycles, last_addr);
                        }
                        top->resp_value_i = 0;
                    } else {
                        /* LOAD / FETCH */
                        if (last_addr == UART_RX_DATA || last_addr == UART_RX_IRQ ||
                            last_addr == UART_TX_READ || last_addr == UART_TX_BUSY) {
                            top->resp_value_i = 0;
                        } else if (last_addr >= RAM_BASE && last_addr < RAM_BASE + RAM_SIZE) {
                            top->resp_value_i = mem_read32(last_addr);
                        } else if (last_addr >= BOOTROM_BASE &&
                                   last_addr < BOOTROM_BASE + BOOTROM_SIZE) {
                            top->resp_value_i = mem_read32(last_addr);
                        } else if (last_addr >= CLINT_BASE && last_addr < CLINT_BASE + CLINT_SIZE) {
                            top->resp_value_i = clint_read32(last_addr - CLINT_BASE);
                        } else if (last_addr >= PLIC_BASE && last_addr < PLIC_BASE + PLIC_SIZE) {
                            top->resp_value_i = plic_read32(last_addr - PLIC_BASE);
                        } else {
                            if (!bus_fault_caught) {
                                bus_fault_caught = 1;
                                fprintf(stderr,
                                        "\n!!! BUS FAULT: READ from unmapped PA 0x%08x !!!\n",
                                        last_addr);
                                dump_state("BUS FAULT (READ from unmapped PA)", top, cycles,
                                           last_addr);
                            }
                            top->resp_value_i = 0;
                        }
                    }
                    processing = 0;
                }
            } else {
                top->resp_valid_i = 0;
            }

            /* Update CLINT & PLIC, drive IRQs */
            bool msi = false, mti = false, mei = false, sei = false;
            clint_update(&msi, &mti);
            plic_update(&mei, &sei);
            top->m_timer_irq_i = mti;
            top->m_soft_irq_i = msi;
            top->m_ext_irq_i = mei;
            top->s_ext_irq_i = sei;
        }

        top->eval();
        if (cycles > START_CYCLE)
            tfp->dump(main_time++);
        if (top->clk_i)
            cycles++;

        /* ── PC history & crash detection ──────────────────────── */
        if (top->clk_i) {
            uint32_t pc = top->rootp->mmu_tb->core_inst->pc_q;
            uint32_t core_st = top->rootp->mmu_tb->core_inst->state_q;
            uint32_t next_st = top->rootp->mmu_tb->core_inst->next_state;
            uint32_t mmu_st = top->rootp->mmu_tb->mmu0->state_q;
            uint32_t instr = top->rootp->mmu_tb->core_inst->__PVT__fe_instr_q;

            /* Record PC history on commit/trap/int */
            if (core_st == 6 || core_st == 7 || core_st == 9 || core_st == 10) {
                uint32_t ra_val = top->rootp->mmu_tb->core_inst->__PVT__regs__DOT__registers[1];
                pc_hist_entry_t *e = &pc_hist[pc_hist_idx % PC_HIST_SIZE];
                e->cycle = cycles;
                e->pc = pc;
                e->core_st = core_st;
                e->mmu_st = mmu_st;
                e->bus_addr = last_addr;
                e->instr = instr;
                e->next_state = next_st;
                e->ra = ra_val;
                pc_hist_idx++;
            }
            uint64_t a = 862158000;
            uint64_t b = 5000;

            /* Sync print: count fetch transitions (FETCH → anything else) */
            if (prev_core_st == 0 && core_st != 0) {
                fetch_count++;
                // if (fetch_count % 1000000 == 0){
                // if (fetch_count % 100000 == 0){
                // if (fetch_count >= 284020){
                // if (fetch_count >= 283480){
                // if (fetch_count >= 428482000){
                //         if (fetch_count >= a){
                //         // if (fetch_count >= 20){
                //             if(fetch_count % b == 0){
                //             fprintf(stderr, "[RTL] fetch=%lu pc=0x%08x\n", fetch_count, pc);
                //             rtl_core_dump(top, fetch_count);
                //             // printf("========================\n");
                //             printf("%lu\n", fetch_count - a);
                // if(fetch_count > a + (b*100000)){
                //     fflush(stdout);
                //     fflush(stderr);
                //     printf("Done\n");
                //     fflush(stdout);
                //     while(1);
                // }
                //             // usleep(100);
                //             }
                //         }
            }
            prev_core_st = core_st;

            /* Log strncpy_from_user prologue store (sw ra, 76(sp)) */
            if (pc == 0xc0380508 && core_st == 6) {
                prologue_count++;
                prologue_seen = 1;
                uint32_t ra_val = top->rootp->mmu_tb->core_inst->__PVT__regs__DOT__registers[1];
                uint32_t sp_val = top->rootp->mmu_tb->core_inst->__PVT__regs__DOT__registers[2];
                fprintf(stderr, "[%lu] PROLOGUE #%d sw ra: ra=0x%08x sp=0x%08x bus=0x%08x\n",
                        cycles, prologue_count, ra_val, sp_val, last_addr);
                fflush(stderr);
            }
            /* Log strncpy_from_user epilogue load (lw ra, 76(sp)) */
            if (pc == 0xc038064c && core_st == 6) {
                epilogue_count++;
                uint32_t ra_val = top->rootp->mmu_tb->core_inst->__PVT__regs__DOT__registers[1];
                uint32_t sp_val = top->rootp->mmu_tb->core_inst->__PVT__regs__DOT__registers[2];
                uint32_t bus_addr_acc = last_addr;
                /* Also read RAM directly to check what's there */
                uint32_t mem_val = 0;
                if (bus_addr_acc >= RAM_BASE && bus_addr_acc < RAM_BASE + RAM_SIZE)
                    memcpy(&mem_val, &ram[bus_addr_acc - RAM_BASE], 4);
                fprintf(
                    stderr,
                    "[%lu] EPILOGUE #%d lw ra: ra=0x%08x sp=0x%08x bus=0x%08x ram[bus]=0x%08x\n",
                    cycles, epilogue_count, ra_val, sp_val, bus_addr_acc, mem_val);
                fflush(stderr);
            }

            /* Catch PC = 0 (NULL jump) outside of reset */
            if (pc == 0 && cycles > 100 && !pc_zero_caught) {
                pc_zero_caught = 1;
                dump_state("PC=0 DETECTED", top, cycles, last_addr);
            }
        }
    }

    /* Cleanup */
    top->final();
    tfp->close();
    delete top;
    delete tfp;
    free(ram);
    return 0;
}
