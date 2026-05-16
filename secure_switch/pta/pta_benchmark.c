// pta_benchmark.c -- Pseudo Trusted Application for Cortex-A53 (AArch64)
//
// This PTA runs inside the OP-TEE kernel (not as a userspace TA) so it
// can directly access physical MMIO registers and the ARM PMU cycle counter.
// It's compiled into the OP-TEE OS image via the 0002-add-benchmark-pta.patch
// applied by the PetaLinux optee-os bbappend recipe.
//
// The host application (optee_benchmark) calls into this PTA via the
// standard GlobalPlatform TEE Client API. The call path is:
//
//   Linux: TEEC_InvokeCommand() -> ioctl(/dev/tee0) -> SMC
//   EL3:   TF-A fast-path -> forward to OP-TEE at S-EL1
//   S-EL1: OP-TEE dispatcher -> pta_invoke() -> io_read32()
//   Return: SMC return -> ioctl returns -> TEEC_InvokeCommand returns
//
// Build integration (PetaLinux / Yocto):
//   The 0002 patch adds this file to optee_os/core/pta/ and the bbappend sets:
//     CFG_BENCHMARK_PTA=y
//     CFG_SWITCH_BASE=0xA0001000   (from Vivado's assign_bd_address)
//
//   The patch also adds to plat-zynqmp/main.c:
//     register_phys_mem(MEM_AREA_IO_SEC, CFG_SWITCH_BASE, 0x1000)

#include <compiler.h>
#include <io.h>
#include <kernel/pseudo_ta.h>
#include <mm/core_memprot.h>
#include <string.h>
#include <trace.h>

#define PTA_NAME "benchmark.pta"

#define PTA_BENCHMARK_UUID \
	{ 0xb2c3d4e5, 0x6789, 0xabcd, \
		{ 0xef, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd } }

#define PTA_CMD_NOP		0
#define PTA_CMD_AXI_READ	1
#define PTA_CMD_AXI_READ_N	2

#ifndef CFG_SWITCH_BASE
#error "CFG_SWITCH_BASE must be defined (secure switch peripheral physical address)"
#endif

#define SWITCH_PHYS	((paddr_t)CFG_SWITCH_BASE)
#define SWITCH_SIZE	0x1000


// ----------------------------------------------------------------------------
// ARM PMU cycle counter (Cortex-A53, AArch64 system register interface)
//
// PMCCNTR_EL0 counts CPU cycles. We enable it, reset it to zero, then
// read it before and after the operation we're measuring. The delta gives
// us a cycle-accurate cost that's independent of clock speed.
//
// On A53 the counter is 64 bits (vs 32 on A9), but we truncate to u32
// when returning to the host since our measurements are well under 2^32.
// ----------------------------------------------------------------------------

static inline void pmu_enable(void)
{
	uint32_t val;

	// PMCR_EL0: set E (enable) and C (reset cycle counter)
	asm volatile("mrs %0, pmcr_el0" : "=r"(val));
	val |= (1 << 0) | (1 << 2);  /* E | C */
	asm volatile("msr pmcr_el0, %0" : : "r"(val));

	// PMCNTENSET_EL0: enable the cycle counter specifically (bit 31)
	asm volatile("msr pmcntenset_el0, %0" : : "r"((uint32_t)(1U << 31)));

	asm volatile("isb");
}

static inline uint64_t read_cycles(void)
{
	uint64_t cnt;

	asm volatile("isb" ::: "memory");
	asm volatile("mrs %0, pmccntr_el0" : "=r"(cnt));
	return cnt;
}


// ----------------------------------------------------------------------------
// Session management
//
// On session open, we look up the virtual address for our FPGA peripheral.
// phys_to_virt() works because the address was registered as MEM_AREA_IO_SEC
// in plat-zynqmp/main.c (via the 0002 patch). We store the VA in the
// session context so each command can use it without re-mapping.
// ----------------------------------------------------------------------------

static TEE_Result pta_open(uint32_t param_types __unused,
			   TEE_Param params[4] __unused,
			   void **sess_ctx)
{
	vaddr_t va;

	va = (vaddr_t)phys_to_virt(SWITCH_PHYS, MEM_AREA_IO_SEC, SWITCH_SIZE);
	if (!va) {
		EMSG("phys_to_virt(0x%" PRIxPA ") failed — is the address in "
		     "the platform secure I/O map?", SWITCH_PHYS);
		return TEE_ERROR_GENERIC;
	}

	*sess_ctx = (void *)va;
	DMSG("Mapped secure switch at PA 0x%" PRIxPA " -> VA %p",
	     SWITCH_PHYS, (void *)va);
	return TEE_SUCCESS;
}


// ----------------------------------------------------------------------------
// CMD_NOP: do nothing, return immediately.
// The host times the full round-trip to measure pure SMC overhead.
// ----------------------------------------------------------------------------

static TEE_Result cmd_nop(uint32_t param_types,
			  TEE_Param params[4] __unused)
{
	if (param_types != TEE_PARAM_TYPES(TEE_PARAM_TYPE_NONE,
					   TEE_PARAM_TYPE_NONE,
					   TEE_PARAM_TYPE_NONE,
					   TEE_PARAM_TYPE_NONE))
		return TEE_ERROR_BAD_PARAMETERS;

	return TEE_SUCCESS;
}


// ----------------------------------------------------------------------------
// CMD_AXI_READ: single MMIO read with cycle counting.
//
// We take four cycle counter snapshots to give two granularities:
//   c_axi = cycles for just the io_read32 (the AXI transaction)
//   c_total = cycles for the entire command (includes PMU setup overhead)
// ----------------------------------------------------------------------------

static TEE_Result cmd_axi_read(uint32_t param_types,
			       TEE_Param params[4],
			       vaddr_t switch_va)
{
	uint64_t c_start, c_axi_start, c_axi_end, c_end;
	uint32_t val;

	if (param_types != TEE_PARAM_TYPES(TEE_PARAM_TYPE_VALUE_OUTPUT,
					   TEE_PARAM_TYPE_VALUE_OUTPUT,
					   TEE_PARAM_TYPE_NONE,
					   TEE_PARAM_TYPE_NONE))
		return TEE_ERROR_BAD_PARAMETERS;

	pmu_enable();

	c_start = read_cycles();

	c_axi_start = read_cycles();
	val = io_read32(switch_va);
	c_axi_end = read_cycles();

	c_end = read_cycles();

	params[0].value.a = val;
	params[0].value.b = (uint32_t)(c_axi_end - c_axi_start);
	params[1].value.a = (uint32_t)(c_end - c_start);
	params[1].value.b = 0;

	return TEE_SUCCESS;
}


// ----------------------------------------------------------------------------
// CMD_AXI_READ_N: N consecutive MMIO reads in a single SMC invocation.
//
// Used for the multi-read sweep: by varying N and plotting total cycles,
// the slope gives us the marginal cost per AXI read and the y-intercept
// gives us the fixed PTA dispatch overhead.
// ----------------------------------------------------------------------------

static TEE_Result cmd_axi_read_n(uint32_t param_types,
				 TEE_Param params[4],
				 vaddr_t switch_va)
{
	uint64_t c_start, c_end;
	uint32_t n, val = 0;
	uint32_t i;

	if (param_types != TEE_PARAM_TYPES(TEE_PARAM_TYPE_VALUE_INOUT,
					   TEE_PARAM_TYPE_VALUE_OUTPUT,
					   TEE_PARAM_TYPE_NONE,
					   TEE_PARAM_TYPE_NONE))
		return TEE_ERROR_BAD_PARAMETERS;

	n = params[0].value.a;
	if (n < 1 || n > 16)
		return TEE_ERROR_BAD_PARAMETERS;

	pmu_enable();

	c_start = read_cycles();
	for (i = 0; i < n; i++)
		val = io_read32(switch_va);
	c_end = read_cycles();

	params[0].value.b = val;
	params[1].value.a = (uint32_t)(c_end - c_start);
	params[1].value.b = 0;

	return TEE_SUCCESS;
}


// ----------------------------------------------------------------------------
// Command dispatch
// ----------------------------------------------------------------------------

static TEE_Result pta_invoke(void *sess_ctx,
			     uint32_t cmd_id, uint32_t param_types,
			     TEE_Param params[4])
{
	vaddr_t switch_va = (vaddr_t)sess_ctx;

	switch (cmd_id) {
	case PTA_CMD_NOP:
		return cmd_nop(param_types, params);
	case PTA_CMD_AXI_READ:
		return cmd_axi_read(param_types, params, switch_va);
	case PTA_CMD_AXI_READ_N:
		return cmd_axi_read_n(param_types, params, switch_va);
	default:
		return TEE_ERROR_BAD_PARAMETERS;
	}
}

pseudo_ta_register(.uuid = PTA_BENCHMARK_UUID,
		   .name = PTA_NAME,
		   .flags = PTA_DEFAULT_FLAGS,
		   .open_session_entry_point = pta_open,
		   .invoke_command_entry_point = pta_invoke);
