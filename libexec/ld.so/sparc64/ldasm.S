/*	$OpenBSD: ldasm.S,v 1.47 2019/05/10 13:29:21 guenther Exp $	*/
/*	$NetBSD: rtld_start.S,v 1.5 2001/08/14 22:17:48 eeh Exp $	*/

/*
 * Copyright (c) 2001 Jason L. Wright (jason@thought.net)
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 * ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

/*-
 * Copyright (c) 2000 Eduardo Horvath.
 * Copyright (c) 1999 The NetBSD Foundation, Inc.
 * All rights reserved.
 *
 * This code is derived from software contributed to The NetBSD Foundation
 * by Christos Zoulas and Paul Kranenburg.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *	This product includes software developed by the NetBSD
 *	Foundation, Inc. and its contributors.
 * 4. Neither the name of The NetBSD Foundation nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE NETBSD FOUNDATION, INC. AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include <sys/syscall.h>
#include <machine/trap.h>
#include <machine/asm.h>
#define	_LOCORE
#include <machine/frame.h>

/*
 * ELF:
 *	On startup the stack should contain 16 extended word register save
 *	area, followed by the arg count, etc.
 *
 * _rtld() expects the stack pointer to point to two longwords for argument
 *	return followed by argc, etc.  We need to create a pointer to
 *	&argc + 16 and pass that in.  The return args will be in those
 *	locations.
 */

/* Offset of ARGC from bottom of stack */
#define	ARGC	CC64FSZ
/* XXX - DL_DATA_SIZE should be (9*8), but I can't think right now. */
#define DL_DATA_SIZE (16*8)

	.section .boot.text,"ax",@progbits
	.align	16
	.register %g2,#scratch

_ENTRY(_dl_start)
	sub	%g0, %g0, %fp		! clear frame
	sub	%sp, 48 + DL_DATA_SIZE, %sp	! make room for dl_data
	add	%sp, BIAS + ARGC, %l3

	add	%l3, DL_DATA_SIZE, %o0
	mov	%o0, %l0

	/*
	 * need to figure out where _DYNAMIC is located, newer binutils
	 * does not fill in GOT to read _DYNAMIC before relocation.
	 */
	call	0f
	 nop
	call	_DYNAMIC+8		! not executed (no delay needed)
0:	ld	[%o7+8], %o2		! load stub call instruction
	sll	%o2, 2, %o2		! extract PC offset
	sra	%o2, 0, %o2		! sign-extend

	add	%o2, %o7, %o2		! real &_DYNAMIC

	call	_dl_boot_bind		! _dl_boot_bind(sp,dl_data,dynamicp)
	 mov	%l3, %o1

	mov	%l3, %o3
	ldx	[%l0], %l3		! argc = *sp
	sllx	%l3, 3, %l3		! argc *= sizeof(long)
	addx	%l0, 8, %o0		! argv = [sp + argc]
	addx	%l0, 16, %o1		! envp = sp + 16 +
	addx	%o1, %l3, %o1		!	+ argc

	addx	%o3, (7*8), %l2
	ldx	[%l2], %o2		! loff = dl_data[AUX_base];

	call	_dl_boot		! _dl_boot(argv,envp,loff,dl_data)
	 nop

	add	%sp, 48 + DL_DATA_SIZE, %sp	! restore stack

1:	call	2f
	 sethi	%hi(_GLOBAL_OFFSET_TABLE_+(.-1b)), %l7
2:	or	%l7, %lo(_GLOBAL_OFFSET_TABLE_+(.-1b)), %l7
	add	%l7, %o7, %l7

	jmp	%o0
	 ldx	[%l7 + _dl_dtors], %g1	! %g1 = cleanup
END(_dl_start)

	/*
	 * We have two separate entry points to the runtime linker.
	 * I'm implementing this following the SPARC v9 ABI spec.
	 *
	 * _dl_bind_start_0(x, y) is called from .PLT0, and is used for
	 * PLT entries above 32768.
	 *
	 * _dl_bind_start_1(x, y) is called from .PLT1, and is used for
	 * PLT entries below 32768.
	 *
	 * The first two entries of PLT2 contain the xword object pointer.
	 *
	 * These routines are called with two longword arguments,
	 * x and y.  To calculate the address of the entry,
	 * _dl_bind_start_1(x, y) does:
	 *
	 *	n = x >> 15;
	 *
	 * and _dl_bind_start_0(x, y) does:
	 *
	 *	i = x - y + 8 - 32768*32;
	 *	n = 32768 + (i/5120)*160 + (i%5120)/24;
	 *
	 * Neither routine needs to issue a save since it's already been
	 * done in the PLT entry.
	 */

	.text
_ENTRY(_dl_bind_start_0)		# (x, y)
	sethi	%hi(32768*32-8), %l1
	sub	%o0, %o1, %l0		/* x - y */
	or	%l1, %lo(32768*32-8), %l1
	sub	%l0, %l1, %l0		/* x - y + 8 - 32768*32 */

	sethi	%hi(5120), %l1
	sdivx	%l0, %l1, %l1		/* Calculate i/5120 */
	ldx	[%o1 + (10*4)], %o0	/* Load object pointer from PLT2 */
	sllx	%l1, 2, %l2
	add	%l1, %l2, %l2
	sllx	%l2, 10, %l2
	sub	%l0, %l2, %l2		/* And i%5120 */

	/* Let the division churn for a bit. */
	sdivx	%l2, 24, %l4		/* (i%5120)/24 */

	/* 160 is (32 * 5) or (32 * (4 + 1)) */
	sllx	%l1, 2, %l3		/* 4 * (i/5120) */
	add	%l1, %l3, %l3		/* 5 * (i/5120) */
	sllx	%l3, 5, %l3		/* 32 * 5 * (i/5120) */

	sethi	%hi(32768), %l6
	add	%l3, %l4, %l5		/* %l5 = (i/5120)*160 + (i%5120)/24; */
	add	%l5, %l6, %l5

	call	_dl_bind		/* Call _dl_bind(obj, offset) */
	 mov	%l5, %o1

	jmp	%o0			/* return value == function address */
	 restore			/* Dump our stack frame */
END(_dl_bind_start_0)

_ENTRY(_dl_bind_start_1)		# (x, y)
	srax	%o0, 15, %o2		/* %o0 is the index to our PLT slot */

	ldx	[%o1 + 8], %o0		/* The object pointer is at [%o1 + 8] */

	call	_dl_bind		/* Call _dl_bind(obj, offset) */
	 mov	%o2, %o1

	jmp	%o0			/* return value == function address */
	 restore			/* Dump our stack frame */
END(_dl_bind_start_1)
