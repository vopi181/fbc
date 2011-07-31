#!/usr/bin/make -f
#
# This is fbc's toplevel makefile whopper, please enjoy it. It builds the
# compiler (fbc) and the runtime (libfb*, fbrt0). Try 'make help' for
# information on what you can configure.
#
# Cross-compilation and building a cross-compiler is supported similar to
# autoconf: through the HOST and TARGET variables that can be set to GNU
# triplets. By default TARGET is the same as HOST, and HOST is the same as
# the build system, which is guessed mostly via uname. In case the triplet
# parsing or default system detection fails, please fix it and make it work!
# Or set HOST_OS, HOST_ARCH and/or TARGET_OS, TARGET_ARCH directly.
#
# FB OS names:
#    dos cygwin darwin freebsd linux netbsd openbsd solaris win32 xbox
#    (where 'dos' should be 'djgpp', and 'win32' should be 'mingw')
# FB architecture names:
#    386 486 586 686 x86_64 sparc sparc64 powerpc64
# Note: In the runtime, the win32 parts are used for both mingw and cygwin,
# so there we have HOST_MINGW/CYGWIN and the HOST_WIN32 common to both.
# In the makefile/compiler win32 means just mingw though.
#
# FB directory layout:
#    a) Default (for Linux /usr[/local] installations, and also for MinGW):
#          bin/target-fbc-suffix
#          bin/target-binutils
#          include/target-freebasic-suffix/fbgfx.bi
#          lib/target-freebasic-suffix/fbgfx.bi
#    b) Standalone (for self-contained DOS/Windows installations):
#          target-fbc-suffix
#          bin/target-binutils
#          target-include-suffix/fbgfx.bi
#          target-lib-suffix/libfb.a
#
# libbfd tips:
#    fbc uses libbfd to add and read out extra information from object files.
#    It's an optional but convenient feature. (see DISABLE_OBJINFO)
#    Read more here: <http://www.freebasic.net/wiki/wikka.php?wakka=DevObjinfo>
#    For the releases made by the fbc project, fbc is linked against a static
#    libbfd 2.17,
#        a) to avoid dependencies on a shared libbfd, because many Linux
#           distributions have different versions of it, and
#        b) to avoid licensing conflicts between fbc (GPLv2) and
#           statically-linked libbfd > 2.17 (GPLv3).
#
# XBox/OpenXDK-related tips (TODO: Test me, update me!)
#  - Install OpenXDK as usual (preferably from SVN if there are no recent
#    releases). Apply openxdk/configure.in-mingw.patch if necessary.
#  - Replace $OPENXDK/bin/i386-pc-xbox-gcc with the one from
#    openxdk/i386-pc-xbox-gcc - this avoids having to rebuild gcc while still
#    getting the OpenXDK include and lib directories instead of the MinGW ones
#    so that configure will work correctly. Modify this script if needed to
#    run MinGW gcc (the current one should work in MSYS) or if OpenXDK is
#    installed somewhere else.
#  - !!!WRITEME!!! cp $MINGW/include/{x,y,z}.h $OPENXDK/i386-pc-xbox/include/
#  - Make sure $OPENXDK/bin is in $PATH
#      export PATH=$PATH:/usr/local/openxdk/bin
#  - Build for or enable the "i386-pc-xbox" target.
#

FBC := fbc
CC := gcc
CFLAGS := -O2
AR := ar

-include config.mk

# The build directory
ifndef new
  new := new
endif

-include $(new)/config.mk

#
# Triplet parsing code
#

triplet-oops = \
  $(error Sorry, '$(1)' does not look like one of the expected triplets. \
          Maybe the makefile should be changed to recognize it.)

# Canonical name to FB name translation
parse-os = \
  $(or $(findstring cygwin,$(1)), \
       $(findstring darwin,$(1)), \
       $(findstring freebsd,$(1)), \
       $(findstring linux,$(1)), \
       $(and $(findstring mingw,$(1)), win32), \
       $(and $(findstring djgpp,$(1)), dos), \
       $(findstring netbsd,$(1)), \
       $(findstring openbsd,$(1)), \
       $(findstring solaris,$(1)), \
       $(findstring xbox,$(1)), \
       $(call triplet-oops,$(2)))

parse-arch = \
  $(or $(and $(filter i386,$(1)),386), \
       $(and $(filter i486,$(1)),486), \
       $(and $(filter i586,$(1)),586), \
       $(and $(filter i686,$(1)),686), \
       $(filter x86_64 sparc sparc64 powerpc64,$(1)), \
       $(call triplet-oops,$(2)))

# os = {all the words 3..EOL | the last word if 3..EOL was empty}
# 'i686 pc linux gnu' -> 'linux gnu'
# 'mingw32'           -> 'mingw32'
extract-os = $(or $(wordlist 3,$(words $(1)),$(1)),$(lastword $(1)))

# arch = iif(has >= 2 words, first word, unknown)
# 'i686 pc linux gnu' -> 'i686'
# 'mingw32'           -> 'unknown'
extract-arch = $(if $(word 2,$(1)),$(firstword $(1)),unknown)

# In autoconf we used a shell case statement and checked for *-*-mingw*, but
# here we convert 'i686-pc-mingw32' to 'i686 pc mingw32' and then use make's
# word/text processing functions to analyze it.
triplet-os  = $(call parse-os,$(call extract-os,$(subst -, ,$(1))),$(1))
triplet-arch = $(call parse-arch,$(call extract-arch,$(subst -, ,$(1))),$(1))

#
# Host/target system determination
#

ifdef HOST
  # Cross-compile fbc to run on this HOST
  HOST_PREFIX := $(HOST)-
  ifndef HOST_OS
    HOST_OS := $(call triplet-os,$(HOST))
  endif
  ifndef HOST_ARCH
    HOST_ARCH := $(call triplet-arch,$(HOST))
  endif
else
  # No HOST given, so guess the build OS & arch via uname or something else.
  # uname is available on every system we currently support, except on
  # Windows with MinGW but not MSYS, we try to detect that below.

  ifndef HOST_OS
    uname := $(shell uname)
    ifneq ($(findstring CYGWIN,$(uname)),)
      HOST_OS := cygwin
    endif
    ifeq ($(uname),Darwin)
      HOST_OS := darwin
    endif
    ifeq ($(uname),FreeBSD)
      HOST_OS := freebsd
    endif
    ifeq ($(uname),Linux)
      HOST_OS := linux
    endif
    ifneq ($(findstring MINGW,$(uname)),)
      HOST_OS := win32
    endif
    ifeq ($(uname),MS-DOS)
      HOST_OS := dos
    endif
    ifeq ($(uname),NetBSD)
      HOST_OS := netbsd
    endif
    ifeq ($(uname),OpenBSD)
      HOST_OS := openbsd
    endif

#    # No output from uname? Maybe it's DJGPP without sh etc., or MinGW without
#    # MSYS. So, check COMSPEC. That's probably not the best thing to do,
#    # but it lets us do builds without requiring MSYS to be installed, which
#    # is nice. While at it we also assume that we must use DOS-style commands,
#    # instead of Unixy ones.
#    # As far as the HOST_ARCH is concerned, for DOS we'll always default to
#    # i386 anyways, and for Windows, if uname failed above, then we won't
#    # bother trying uname -m below either, so default to something useful.
#    ifndef uname
#      comspec := $(shell echo %COMSPEC%)
#      ifneq ($(findstring COMMAND.COM,$(comspec)),)
#        HOST_OS := dos
#        ENABLE_DOSCMD := YesPlease
#      endif
#      ifneq ($(findstring cmd.exe,$(comspec)),)
#        HOST_OS := win32
#        ENABLE_DOSCMD := YesPlease
#        ifndef HOST_ARCH
#          HOST_ARCH := 486
#        endif
#      endif
#    endif
#
# TODO: In case of ENABLE_DOSCMD, we'd have to use normal mkdir/rmdir
# instead of mkdir -p or rmdir -p, \ instead of / path separators,
# del instead of rm -f and trim down command line even more,
# because anything that needs to go through cmd.exe is limited to 8k chars.
# Note that unless an recipe uses cmd.exe shell syntax like ';' or redirection,
# the limit doesn't apply (seemed like it during testing anyways).

    ifndef HOST_OS
      $(error Sorry, the OS could not be identified. Maybe the makefile \
              should be fixed. 'uname' returned: '$(uname)')
    endif
  endif

  # For DOS, just build for i386 and don't bother with uname -m.
  # Also: a) DJGPP's uname -m just returns 'pc', and b) it doesn't seem to work
  # from $(shell) at all, maybe it's an issue with the COMMAND.COM?
  ifndef HOST_ARCH
    ifeq ($(HOST_OS),dos)
      HOST_ARCH := 386
    endif
  endif

  ifndef HOST_ARCH
    uname_m := $(shell uname -m)
    ifeq ($(uname_m),i386)
      HOST_ARCH = 386
    endif
    ifeq ($(uname_m),i486)
      HOST_ARCH = 486
    endif
    ifeq ($(uname_m),i586)
      HOST_ARCH = 586
    endif
    ifeq ($(uname_m),i686)
      HOST_ARCH = 686
    endif
    ifeq ($(uname_m),x86_64)
      HOST_ARCH = x86_64
    endif
    ifeq ($(uname_m),sparc)
      HOST_ARCH = sparc
    endif
    ifeq ($(uname_m),sparc64)
      HOST_ARCH = sparc64
    endif
    ifeq ($(uname_m),powerpc64)
      HOST_ARCH = powerpc64
    endif

    ifndef HOST_ARCH
      $(error Sorry, the arch could not be identified. Maybe the makefile \
              should be fixed. 'uname -m' returned: '$(uname_m)')
    endif
  endif
endif

ifdef TARGET
  # TARGET given, so parse it.
  TARGET_PREFIX := $(TARGET)-
  ifndef TARGET_OS
    TARGET_OS := $(call triplet-os,$(TARGET))
  endif
  ifndef TARGET_ARCH
    TARGET_ARCH := $(call triplet-arch,$(TARGET))
  endif
else
  # No TARGET given, so set the same values/defines as for HOST
  ifdef HOST
    TARGET := $(HOST)
    TARGET_PREFIX := $(HOST_PREFIX)
  endif
  ifndef TARGET_OS
    TARGET_OS := $(HOST_OS)
  endif
  ifndef TARGET_ARCH
    TARGET_ARCH := $(HOST_ARCH)
  endif
endif

#
# System specific configuration
#

ifndef HOST_FBC
  HOST_FBC := $(HOST_PREFIX)$(FBC)
endif
ifndef HOST_CC
  HOST_CC := $(HOST_PREFIX)$(CC)
endif
ifndef TARGET_AR
  TARGET_AR := $(TARGET_PREFIX)$(AR)
endif
ifndef TARGET_CC
  TARGET_CC := $(TARGET_PREFIX)$(CC)
endif

ifneq ($(filter cygwin dos win32,$(HOST_OS)),)
  EXEEXT := .exe
endif

# Default prefix is /usr/local, except when cross-compiling, then you typically
# don't want to install into the build system, and when on Windows (with MinGW),
# installing into /usr/local isn't all that helpful (especially if MSYS isn't
# installed). For Cygwin it's probably always ok to use /usr/local, isn't it?
ifndef prefix
  ifdef HOST
    prefix := .
  else
    ifneq ($(filter dos win32,$(HOST_OS)),)
      prefix := .
    else
      prefix := /usr/local
    endif
  endif
endif

ifeq ($(TARGET_OS),dos)
  # Don't build libfbmt for DOS
  DISABLE_MT := YesPlease
  # And also no OpenGL support
  DISABLE_OPENGL := YesPlease
endif

# Enable the default target in the compiler, and set the default triplet,
# which can be empty.
ifeq ($(TARGET_OS),cygwin)
  ENABLE_CYGWIN := YesPlease
  TRIPLET_CYGWIN:=$(TARGET)
endif
ifeq ($(TARGET_OS),darwin)
  ENABLE_DARWIN := YesPlease
  TRIPLET_DARWIN:=$(TARGET)
endif
ifeq ($(TARGET_OS),dos)
  ENABLE_DOS := YesPlease
  TRIPLET_DOS:=$(TARGET)
endif
ifeq ($(TARGET_OS),freebsd)
  ENABLE_FREEBSD := YesPlease
  TRIPLET_FREEBSD:=$(TARGET)
endif
ifeq ($(TARGET_OS),linux)
  ENABLE_LINUX := YesPlease
  TRIPLET_LINUX:=$(TARGET)
endif
ifeq ($(TARGET_OS),win32)
  ENABLE_WIN32 := YesPlease
  TRIPLET_WIN32:=$(TARGET)
endif
ifeq ($(TARGET_OS),netbsd)
  ENABLE_NETBSD := YesPlease
  TRIPLET_NETBSD:=$(TARGET)
endif
ifeq ($(TARGET_OS),openbsd)
  ENABLE_OPENBSD := YesPlease
  TRIPLET_OPENBSD:=$(TARGET)
endif
ifeq ($(TARGET_OS),solaris)
  ENABLE_SOLARIS := YesPlease
  TRIPLET_SOLARIS:=$(TARGET)
endif
ifeq ($(TARGET_OS),xbox)
  ENABLE_XBOX := YesPlease
  TRIPLET_XBOX:=$(TARGET)
endif

#
# Directory layout setup
#

# Protect against dangerous empty path variables, we do not want to end up with
# 'rm -rf /'. Assuming <nothing> means '.'.
ifndef prefix
  override prefix := .
endif
ifndef new
  override new := .
endif

ifdef ENABLE_STANDALONE
  newbin := $(new)
  newlib := $(new)/$(TARGET_PREFIX)lib$(SUFFIX)
  prefixbin := $(prefix)
  prefixlib := $(prefix)/$(TARGET_PREFIX)lib$(SUFFIX)
else
  newbin := $(new)/bin
  newlib := $(new)/lib/$(TARGET_PREFIX)freebasic$(SUFFIX)
  prefixbin := $(prefix)/bin
  prefixlib := $(prefix)/lib/$(TARGET_PREFIX)freebasic$(SUFFIX)
endif

FBC_NEW   := $(newbin)/$(TARGET_PREFIX)fbc$(SUFFIX)$(EXEEXT)
FBRT0_NEW := $(newlib)/fbrt0.o
LIBFB_NEW := $(newlib)/libfb.a

FBC_PREFIX   := $(prefixbin)/$(TARGET_PREFIX)fbc$(SUFFIX)$(EXEEXT)
FBRT0_PREFIX := $(prefixlib)/fbrt0.o
LIBFB_PREFIX := $(prefixlib)/libfb.a

ifndef DISABLE_MT
  LIBFBMT_NEW := $(newlib)/libfbmt.a
  LIBFBMT_PREFIX := $(prefixlib)/libfbmt.a
endif

ifndef DISABLE_GFX
  LIBFBGFX_NEW := $(newlib)/libfbgfx.a
  LIBFBGFX_PREFIX := $(prefixlib)/libfbgfx.a
endif

newcompiler := $(new)/compiler
newruntime := $(new)/runtime
FBC_CONFIG := $(newcompiler)/config.bi
LIBFB_CONFIG := $(newruntime)/config.h

#
# Compiler flags
#

FBCFLAGS := $(FBFLAGS) -maxerr 1 -w all -w pedantic
FBCFLAGS += -e -m fbc -include $(FBC_CONFIG)
FBLFLAGS := $(FBFLAGS)
ALLCFLAGS := $(CFLAGS) -Wfatal-errors -Wall -include $(LIBFB_CONFIG)

ifneq ($(filter cygwin win32,$(HOST_OS)),)
  FBLFLAGS += -t 2048
endif

ifndef DISABLE_OBJINFO
  FBLFLAGS += -l bfd -l iberty
  ifeq ($(HOST_OS),cygwin)
    FBLFLAGS += -l intl
  endif
  ifeq ($(HOST_OS),dos)
    FBLFLAGS += -l intl -l z
  endif
  ifeq ($(HOST_OS),freebsd)
    FBLFLAGS += -l intl
  endif
  ifeq ($(HOST_OS),openbsd)
    FBLFLAGS += -l intl
  endif
  ifeq ($(HOST_OS),win32)
    FBLFLAGS += -l user32
  endif
endif

# Some special treatment for xbox. TODO: Test me, update me!
ifeq ($(TARGET_OS),xbox)
  ALLCFLAGS += -DENABLE_XBOX -DDISABLE_CDROM
  ALLCFLAGS += -std=gnu99 -mno-cygwin -nostdlib -nostdinc
  ALLCFLAGS += -ffreestanding -fno-builtin -fno-exceptions
  ALLCFLAGS += -I$(OPENXDK)/i386-pc-xbox/include
  ALLCFLAGS += -I$(OPENXDK)/include
  ALLCFLAGS += -I$(OPENXDK)/include/SDL
endif

#
# Sources
#

FBC_BI := $(FBC_CONFIG)
FBC_BI += compiler/ast.bi
FBC_BI += compiler/ast-op.bi
FBC_BI += compiler/clist.bi
FBC_BI += compiler/dstr.bi
FBC_BI += compiler/emit.bi
FBC_BI += compiler/emitdbg.bi
FBC_BI += compiler/error.bi
FBC_BI += compiler/fb-bfd-bridge.bi
FBC_BI += compiler/fb.bi
FBC_BI += compiler/fbc.bi
FBC_BI += compiler/fbint.bi
FBC_BI += compiler/fb-obj.bi
FBC_BI += compiler/flist.bi
FBC_BI += compiler/hash.bi
FBC_BI += compiler/hlp.bi
FBC_BI += compiler/hlp-str.bi
FBC_BI += compiler/ir.bi
FBC_BI += compiler/lex.bi
FBC_BI += compiler/list.bi
FBC_BI += compiler/parser.bi
FBC_BI += compiler/pool.bi
FBC_BI += compiler/pp.bi
FBC_BI += compiler/reg.bi
FBC_BI += compiler/rtl.bi
FBC_BI += compiler/stabs.bi
FBC_BI += compiler/stack.bi
FBC_BI += compiler/symb.bi

FBC_BAS := $(newcompiler)/ast.o
FBC_BAS += $(newcompiler)/ast-gosub.o
FBC_BAS += $(newcompiler)/ast-helper.o
FBC_BAS += $(newcompiler)/ast-misc.o
FBC_BAS += $(newcompiler)/ast-node-addr.o
FBC_BAS += $(newcompiler)/ast-node-arg.o
FBC_BAS += $(newcompiler)/ast-node-assign.o
FBC_BAS += $(newcompiler)/ast-node-bop.o
FBC_BAS += $(newcompiler)/ast-node-branch.o
FBC_BAS += $(newcompiler)/ast-node-call.o
FBC_BAS += $(newcompiler)/ast-node-check.o
FBC_BAS += $(newcompiler)/ast-node-const.o
FBC_BAS += $(newcompiler)/ast-node-conv.o
FBC_BAS += $(newcompiler)/ast-node-data.o
FBC_BAS += $(newcompiler)/ast-node-decl.o
FBC_BAS += $(newcompiler)/ast-node-enum.o
FBC_BAS += $(newcompiler)/ast-node-field.o
FBC_BAS += $(newcompiler)/ast-node-idx.o
FBC_BAS += $(newcompiler)/ast-node-iif.o
FBC_BAS += $(newcompiler)/ast-node-link.o
FBC_BAS += $(newcompiler)/ast-node-load.o
FBC_BAS += $(newcompiler)/ast-node-mem.o
FBC_BAS += $(newcompiler)/ast-node-misc.o
FBC_BAS += $(newcompiler)/ast-node-namespace.o
FBC_BAS += $(newcompiler)/ast-node-proc.o
FBC_BAS += $(newcompiler)/ast-node-ptr.o
FBC_BAS += $(newcompiler)/ast-node-scope.o
FBC_BAS += $(newcompiler)/ast-node-stack.o
FBC_BAS += $(newcompiler)/ast-node-typeini.o
FBC_BAS += $(newcompiler)/ast-node-uop.o
FBC_BAS += $(newcompiler)/ast-node-var.o
FBC_BAS += $(newcompiler)/ast-optimize.o
FBC_BAS += $(newcompiler)/ast-vectorize.o
FBC_BAS += $(newcompiler)/clist.o
FBC_BAS += $(newcompiler)/dstr.o
FBC_BAS += $(newcompiler)/edbg_stab.o
FBC_BAS += $(newcompiler)/emit.o
FBC_BAS += $(newcompiler)/emit_SSE.o
FBC_BAS += $(newcompiler)/emit_x86.o
FBC_BAS += $(newcompiler)/error.o
FBC_BAS += $(newcompiler)/fb.o
FBC_BAS += $(newcompiler)/fb-main.o
FBC_BAS += $(newcompiler)/fb-objinfo.o
FBC_BAS += $(newcompiler)/fbc.o
ifdef ENABLE_CYGWIN
  FBC_BAS += $(newcompiler)/fbc_cyg.o
endif
ifdef ENABLE_DARWIN
  FBC_BAS += $(newcompiler)/fbc_darwin.o
endif
ifdef ENABLE_DOS
  FBC_BAS += $(newcompiler)/fbc_dos.o
endif
ifdef ENABLE_FREEBSD
  FBC_BAS += $(newcompiler)/fbc_freebsd.o
endif
ifdef ENABLE_LINUX
  FBC_BAS += $(newcompiler)/fbc_linux.o
endif
ifdef ENABLE_NETBSD
  FBC_BAS += $(newcompiler)/fbc_netbsd.o
endif
ifdef ENABLE_OPENBSD
  FBC_BAS += $(newcompiler)/fbc_openbsd.o
endif
ifdef ENABLE_WIN32
  FBC_BAS += $(newcompiler)/fbc_win32.o
endif
ifdef ENABLE_XBOX
  FBC_BAS += $(newcompiler)/fbc_xbox.o
endif
FBC_BAS += $(newcompiler)/flist.o
FBC_BAS += $(newcompiler)/hash.o
FBC_BAS += $(newcompiler)/hlp.o
FBC_BAS += $(newcompiler)/hlp-str.o
FBC_BAS += $(newcompiler)/ir.o
FBC_BAS += $(newcompiler)/ir-hlc.o
FBC_BAS += $(newcompiler)/ir-tac.o
FBC_BAS += $(newcompiler)/lex.o
FBC_BAS += $(newcompiler)/lex-utf.o
FBC_BAS += $(newcompiler)/list.o
FBC_BAS += $(newcompiler)/parser-assignment.o
FBC_BAS += $(newcompiler)/parser-comment.o
FBC_BAS += $(newcompiler)/parser-compound.o
FBC_BAS += $(newcompiler)/parser-compound-do.o
FBC_BAS += $(newcompiler)/parser-compound-extern.o
FBC_BAS += $(newcompiler)/parser-compound-for.o
FBC_BAS += $(newcompiler)/parser-compound-if.o
FBC_BAS += $(newcompiler)/parser-compound-namespace.o
FBC_BAS += $(newcompiler)/parser-compound-scope.o
FBC_BAS += $(newcompiler)/parser-compound-select.o
FBC_BAS += $(newcompiler)/parser-compound-select-const.o
FBC_BAS += $(newcompiler)/parser-compound-while.o
FBC_BAS += $(newcompiler)/parser-compound-with.o
FBC_BAS += $(newcompiler)/parser-decl.o
FBC_BAS += $(newcompiler)/parser-decl-const.o
FBC_BAS += $(newcompiler)/parser-decl-def.o
FBC_BAS += $(newcompiler)/parser-decl-enum.o
FBC_BAS += $(newcompiler)/parser-decl-option.o
FBC_BAS += $(newcompiler)/parser-decl-proc.o
FBC_BAS += $(newcompiler)/parser-decl-proc-params.o
FBC_BAS += $(newcompiler)/parser-decl-struct.o
FBC_BAS += $(newcompiler)/parser-decl-symb-init.o
FBC_BAS += $(newcompiler)/parser-decl-symbtype.o
FBC_BAS += $(newcompiler)/parser-decl-typedef.o
FBC_BAS += $(newcompiler)/parser-decl-var.o
FBC_BAS += $(newcompiler)/parser-expr-atom.o
FBC_BAS += $(newcompiler)/parser-expr-binary.o
FBC_BAS += $(newcompiler)/parser-expr-constant.o
FBC_BAS += $(newcompiler)/parser-expr-function.o
FBC_BAS += $(newcompiler)/parser-expr-unary.o
FBC_BAS += $(newcompiler)/parser-expr-variable.o
FBC_BAS += $(newcompiler)/parser-identifier.o
FBC_BAS += $(newcompiler)/parser-inlineasm.o
FBC_BAS += $(newcompiler)/parser-label.o
FBC_BAS += $(newcompiler)/parser-proc.o
FBC_BAS += $(newcompiler)/parser-proccall-args.o
FBC_BAS += $(newcompiler)/parser-proccall.o
FBC_BAS += $(newcompiler)/parser-quirk-array.o
FBC_BAS += $(newcompiler)/parser-quirk.o
FBC_BAS += $(newcompiler)/parser-quirk-casting.o
FBC_BAS += $(newcompiler)/parser-quirk-console.o
FBC_BAS += $(newcompiler)/parser-quirk-data.o
FBC_BAS += $(newcompiler)/parser-quirk-error.o
FBC_BAS += $(newcompiler)/parser-quirk-file.o
FBC_BAS += $(newcompiler)/parser-quirk-gfx.o
FBC_BAS += $(newcompiler)/parser-quirk-goto-return.o
FBC_BAS += $(newcompiler)/parser-quirk-iif.o
FBC_BAS += $(newcompiler)/parser-quirk-math.o
FBC_BAS += $(newcompiler)/parser-quirk-mem.o
FBC_BAS += $(newcompiler)/parser-quirk-on.o
FBC_BAS += $(newcompiler)/parser-quirk-peekpoke.o
FBC_BAS += $(newcompiler)/parser-quirk-string.o
FBC_BAS += $(newcompiler)/parser-quirk-vafirst.o
FBC_BAS += $(newcompiler)/parser-statement.o
FBC_BAS += $(newcompiler)/parser-toplevel.o
FBC_BAS += $(newcompiler)/pool.o
FBC_BAS += $(newcompiler)/pp.o
FBC_BAS += $(newcompiler)/pp-cond.o
FBC_BAS += $(newcompiler)/pp-define.o
FBC_BAS += $(newcompiler)/pp-pragma.o
FBC_BAS += $(newcompiler)/reg.o
FBC_BAS += $(newcompiler)/rtl.o
FBC_BAS += $(newcompiler)/rtl-array.o
FBC_BAS += $(newcompiler)/rtl-console.o
FBC_BAS += $(newcompiler)/rtl-data.o
FBC_BAS += $(newcompiler)/rtl-error.o
FBC_BAS += $(newcompiler)/rtl-file.o
FBC_BAS += $(newcompiler)/rtl-gfx.o
FBC_BAS += $(newcompiler)/rtl-gosub.o
FBC_BAS += $(newcompiler)/rtl-macro.o
FBC_BAS += $(newcompiler)/rtl-math.o
FBC_BAS += $(newcompiler)/rtl-mem.o
FBC_BAS += $(newcompiler)/rtl-print.o
FBC_BAS += $(newcompiler)/rtl-profile.o
FBC_BAS += $(newcompiler)/rtl-string.o
FBC_BAS += $(newcompiler)/rtl-system.o
FBC_BAS += $(newcompiler)/stack.o
FBC_BAS += $(newcompiler)/symb.o
FBC_BAS += $(newcompiler)/symb-bitfield.o
FBC_BAS += $(newcompiler)/symb-comp.o
FBC_BAS += $(newcompiler)/symb-const.o
FBC_BAS += $(newcompiler)/symb-data.o
FBC_BAS += $(newcompiler)/symb-define.o
FBC_BAS += $(newcompiler)/symb-enum.o
FBC_BAS += $(newcompiler)/symb-keyword.o
FBC_BAS += $(newcompiler)/symb-label.o
FBC_BAS += $(newcompiler)/symb-lib.o
FBC_BAS += $(newcompiler)/symb-mangling.o
FBC_BAS += $(newcompiler)/symb-namespace.o
FBC_BAS += $(newcompiler)/symb-proc.o
FBC_BAS += $(newcompiler)/symb-scope.o
FBC_BAS += $(newcompiler)/symb-struct.o
FBC_BAS += $(newcompiler)/symb-typedef.o
FBC_BAS += $(newcompiler)/symb-var.o

FBC_COBJINFO :=
ifndef DISABLE_OBJINFO
  ifndef ENABLE_FBBFD
    FBC_COBJINFO := $(newcompiler)/c-objinfo.o
  endif
endif

LIBFB_H := $(LIBFB_CONFIG)
LIBFB_H += runtime/fb.h
LIBFB_H += runtime/fb_array.h
LIBFB_H += runtime/fb_colors.h
LIBFB_H += runtime/fb_config.h
LIBFB_H += runtime/fb_con.h
LIBFB_H += runtime/fb_console.h
LIBFB_H += runtime/fb_data.h
LIBFB_H += runtime/fb_datetime.h
LIBFB_H += runtime/fb_device.h
LIBFB_H += runtime/fb_error.h
LIBFB_H += runtime/fb_file.h
LIBFB_H += runtime/fb_hook.h
LIBFB_H += runtime/fb_intern.h
LIBFB_H += runtime/fb_math.h
LIBFB_H += runtime/fb_port.h
LIBFB_H += runtime/fb_printer.h
LIBFB_H += runtime/fb_scancodes.h
LIBFB_H += runtime/fb_serial.h
LIBFB_H += runtime/fb_string.h
LIBFB_H += runtime/fb_system.h
LIBFB_H += runtime/fb_thread.h
LIBFB_H += runtime/fb_unicode.h
LIBFB_H += runtime/libfb_con_print_raw_uni.h
LIBFB_H += runtime/libfb_con_print_tty_uni.h

LIBFB_C := $(newruntime)/libfb_array_boundchk.o
LIBFB_C += $(newruntime)/libfb_array_clear.o
LIBFB_C += $(newruntime)/libfb_array_clear_obj.o
LIBFB_C += $(newruntime)/libfb_array_core.o
LIBFB_C += $(newruntime)/libfb_array_erase.o
LIBFB_C += $(newruntime)/libfb_array_erase_obj.o
LIBFB_C += $(newruntime)/libfb_array_erasestr.o
LIBFB_C += $(newruntime)/libfb_array_lbound.o
LIBFB_C += $(newruntime)/libfb_array_redim.o
LIBFB_C += $(newruntime)/libfb_array_redim_obj.o
LIBFB_C += $(newruntime)/libfb_array_redimpresv.o
LIBFB_C += $(newruntime)/libfb_array_redimpresv_obj.o
LIBFB_C += $(newruntime)/libfb_array_resetdesc.o
LIBFB_C += $(newruntime)/libfb_array_setdesc.o
LIBFB_C += $(newruntime)/libfb_array_tmpdesc.o
LIBFB_C += $(newruntime)/libfb_array_ubound.o
LIBFB_C += $(newruntime)/libfb_assert.o
LIBFB_C += $(newruntime)/libfb_assert_wstr.o
LIBFB_C += $(newruntime)/libfb_con_lineinp.o
LIBFB_C += $(newruntime)/libfb_con_lineinp_wstr.o
LIBFB_C += $(newruntime)/libfb_con_locate.o
LIBFB_C += $(newruntime)/libfb_con_pos.o
LIBFB_C += $(newruntime)/libfb_con_print_raw.o
LIBFB_C += $(newruntime)/libfb_con_print_raw_wstr.o
LIBFB_C += $(newruntime)/libfb_con_print_tty.o
LIBFB_C += $(newruntime)/libfb_con_print_tty_wstr.o
LIBFB_C += $(newruntime)/libfb_con_readline.o
LIBFB_C += $(newruntime)/libfb_data.o
LIBFB_C += $(newruntime)/libfb_data_readbyte.o
LIBFB_C += $(newruntime)/libfb_data_readdouble.o
LIBFB_C += $(newruntime)/libfb_data_readint.o
LIBFB_C += $(newruntime)/libfb_data_readlong.o
LIBFB_C += $(newruntime)/libfb_data_readshort.o
LIBFB_C += $(newruntime)/libfb_data_readsingle.o
LIBFB_C += $(newruntime)/libfb_data_readstr.o
LIBFB_C += $(newruntime)/libfb_data_readubyte.o
LIBFB_C += $(newruntime)/libfb_data_readuint.o
LIBFB_C += $(newruntime)/libfb_data_readulong.o
LIBFB_C += $(newruntime)/libfb_data_readushort.o
LIBFB_C += $(newruntime)/libfb_data_read_wstr.o
LIBFB_C += $(newruntime)/libfb_data_rest.o
LIBFB_C += $(newruntime)/libfb_dev_com.o
LIBFB_C += $(newruntime)/libfb_dev_com_test.o
LIBFB_C += $(newruntime)/libfb_dev_cons_open.o
LIBFB_C += $(newruntime)/libfb_dev_err_open.o
LIBFB_C += $(newruntime)/libfb_dev_file_close.o
LIBFB_C += $(newruntime)/libfb_dev_file_encod_open.o
LIBFB_C += $(newruntime)/libfb_dev_file_encod_read.o
LIBFB_C += $(newruntime)/libfb_dev_file_encod_read_core.o
LIBFB_C += $(newruntime)/libfb_dev_file_encod_readline.o
LIBFB_C += $(newruntime)/libfb_dev_file_encod_readline_wstr.o
LIBFB_C += $(newruntime)/libfb_dev_file_encod_read_wstr.o
LIBFB_C += $(newruntime)/libfb_dev_file_encod_write.o
LIBFB_C += $(newruntime)/libfb_dev_file_encod_write_wstr.o
LIBFB_C += $(newruntime)/libfb_dev_file_eof.o
LIBFB_C += $(newruntime)/libfb_dev_file_flush.o
LIBFB_C += $(newruntime)/libfb_dev_file_lock.o
LIBFB_C += $(newruntime)/libfb_dev_file_open.o
LIBFB_C += $(newruntime)/libfb_dev_file_read.o
LIBFB_C += $(newruntime)/libfb_dev_file_readline.o
LIBFB_C += $(newruntime)/libfb_dev_file_readline_wstr.o
LIBFB_C += $(newruntime)/libfb_dev_file_read_wstr.o
LIBFB_C += $(newruntime)/libfb_dev_file_seek.o
LIBFB_C += $(newruntime)/libfb_dev_file_size.o
LIBFB_C += $(newruntime)/libfb_dev_file_tell.o
LIBFB_C += $(newruntime)/libfb_dev_file_unlock.o
LIBFB_C += $(newruntime)/libfb_dev_file_write.o
LIBFB_C += $(newruntime)/libfb_dev_file_write_wstr.o
LIBFB_C += $(newruntime)/libfb_dev_lpt.o
LIBFB_C += $(newruntime)/libfb_dev_lpt_close.o
LIBFB_C += $(newruntime)/libfb_dev_lpt_test.o
LIBFB_C += $(newruntime)/libfb_dev_lpt_write.o
LIBFB_C += $(newruntime)/libfb_dev_lpt_write_wstr.o
LIBFB_C += $(newruntime)/libfb_dev_scrn.o
LIBFB_C += $(newruntime)/libfb_dev_scrn_close.o
LIBFB_C += $(newruntime)/libfb_dev_scrn_eof.o
LIBFB_C += $(newruntime)/libfb_dev_scrn_init.o
LIBFB_C += $(newruntime)/libfb_dev_scrn_read.o
LIBFB_C += $(newruntime)/libfb_dev_scrn_readline.o
LIBFB_C += $(newruntime)/libfb_dev_scrn_readline_wstr.o
LIBFB_C += $(newruntime)/libfb_dev_scrn_read_wstr.o
LIBFB_C += $(newruntime)/libfb_dev_scrn_write.o
LIBFB_C += $(newruntime)/libfb_dev_scrn_write_wstr.o
LIBFB_C += $(newruntime)/libfb_dev_stdio_close.o
LIBFB_C += $(newruntime)/libfb_error.o
LIBFB_C += $(newruntime)/libfb_error_getset.o
LIBFB_C += $(newruntime)/libfb_error_ptrchk.o
LIBFB_C += $(newruntime)/libfb_exit.o
LIBFB_C += $(newruntime)/libfb_file_attr.o
LIBFB_C += $(newruntime)/libfb_file_close.o
LIBFB_C += $(newruntime)/libfb_file_copy.o
LIBFB_C += $(newruntime)/libfb_file_datetime.o
LIBFB_C += $(newruntime)/libfb_file_encod.o
LIBFB_C += $(newruntime)/libfb_file_eof.o
LIBFB_C += $(newruntime)/libfb_file_exists.o
LIBFB_C += $(newruntime)/libfb_file_free.o
LIBFB_C += $(newruntime)/libfb_file_getarray.o
LIBFB_C += $(newruntime)/libfb_file_get.o
LIBFB_C += $(newruntime)/libfb_file_getstr.o
LIBFB_C += $(newruntime)/libfb_file_get_wstr.o
LIBFB_C += $(newruntime)/libfb_file_input_byte.o
LIBFB_C += $(newruntime)/libfb_file_input_con.o
LIBFB_C += $(newruntime)/libfb_file_input_file.o
LIBFB_C += $(newruntime)/libfb_file_input_float.o
LIBFB_C += $(newruntime)/libfb_file_input_int.o
LIBFB_C += $(newruntime)/libfb_file_input_longint.o
LIBFB_C += $(newruntime)/libfb_file_input_short.o
LIBFB_C += $(newruntime)/libfb_file_input_str.o
LIBFB_C += $(newruntime)/libfb_file_inputstr.o
LIBFB_C += $(newruntime)/libfb_file_input_tok.o
LIBFB_C += $(newruntime)/libfb_file_input_tok_wstr.o
LIBFB_C += $(newruntime)/libfb_file_input_ubyte.o
LIBFB_C += $(newruntime)/libfb_file_input_uint.o
LIBFB_C += $(newruntime)/libfb_file_input_ulongint.o
LIBFB_C += $(newruntime)/libfb_file_input_ushort.o
LIBFB_C += $(newruntime)/libfb_file_input_wstr.o
LIBFB_C += $(newruntime)/libfb_file_kill.o
LIBFB_C += $(newruntime)/libfb_file_len.o
LIBFB_C += $(newruntime)/libfb_file_lineinp.o
LIBFB_C += $(newruntime)/libfb_file_lineinp_wstr.o
LIBFB_C += $(newruntime)/libfb_file_loc.o
LIBFB_C += $(newruntime)/libfb_file_lock.o
LIBFB_C += $(newruntime)/libfb_file_open.o
LIBFB_C += $(newruntime)/libfb_file_opencom.o
LIBFB_C += $(newruntime)/libfb_file_opencons.o
LIBFB_C += $(newruntime)/libfb_file_openencod.o
LIBFB_C += $(newruntime)/libfb_file_openerr.o
LIBFB_C += $(newruntime)/libfb_file_openlpt.o
LIBFB_C += $(newruntime)/libfb_file_openpipe.o
LIBFB_C += $(newruntime)/libfb_file_openscrn.o
LIBFB_C += $(newruntime)/libfb_file_openshort.o
LIBFB_C += $(newruntime)/libfb_file_print.o
LIBFB_C += $(newruntime)/libfb_file_print_wstr.o
LIBFB_C += $(newruntime)/libfb_file_putarray.o
LIBFB_C += $(newruntime)/libfb_file_putback.o
LIBFB_C += $(newruntime)/libfb_file_putback_wstr.o
LIBFB_C += $(newruntime)/libfb_file_put.o
LIBFB_C += $(newruntime)/libfb_file_putstr.o
LIBFB_C += $(newruntime)/libfb_file_put_wstr.o
LIBFB_C += $(newruntime)/libfb_file_reset.o
LIBFB_C += $(newruntime)/libfb_file_seek.o
LIBFB_C += $(newruntime)/libfb_file_size.o
LIBFB_C += $(newruntime)/libfb_file_tell.o
LIBFB_C += $(newruntime)/libfb_file_winputstr.o
LIBFB_C += $(newruntime)/libfb_gosub.o
LIBFB_C += $(newruntime)/libfb_hook_cls.o
LIBFB_C += $(newruntime)/libfb_hook_color.o
LIBFB_C += $(newruntime)/libfb_hook_getsize.o
LIBFB_C += $(newruntime)/libfb_hook_getx.o
LIBFB_C += $(newruntime)/libfb_hook_getxy.o
LIBFB_C += $(newruntime)/libfb_hook_gety.o
LIBFB_C += $(newruntime)/libfb_hook_inkey.o
LIBFB_C += $(newruntime)/libfb_hook_isredir.o
LIBFB_C += $(newruntime)/libfb_hook_lineinp.o
LIBFB_C += $(newruntime)/libfb_hook_lineinp_wstr.o
LIBFB_C += $(newruntime)/libfb_hook_locate_ex.o
LIBFB_C += $(newruntime)/libfb_hook_mouse.o
LIBFB_C += $(newruntime)/libfb_hook_multikey.o
LIBFB_C += $(newruntime)/libfb_hook_pageset.o
LIBFB_C += $(newruntime)/libfb_hook_pcopy.o
LIBFB_C += $(newruntime)/libfb_hook_ports.o
LIBFB_C += $(newruntime)/libfb_hook_printstr.o
LIBFB_C += $(newruntime)/libfb_hook_print_wstr.o
LIBFB_C += $(newruntime)/libfb_hook_readstr.o
LIBFB_C += $(newruntime)/libfb_hook_readxy.o
LIBFB_C += $(newruntime)/libfb_hook_sleep.o
LIBFB_C += $(newruntime)/libfb_hook_view_update.o
LIBFB_C += $(newruntime)/libfb_hook_width.o
LIBFB_C += $(newruntime)/libfb_init.o
LIBFB_C += $(newruntime)/libfb_intl_get.o
LIBFB_C += $(newruntime)/libfb_intl_getdateformat.o
LIBFB_C += $(newruntime)/libfb_intl_getmonthname.o
LIBFB_C += $(newruntime)/libfb_intl_getset.o
LIBFB_C += $(newruntime)/libfb_intl_gettimeformat.o
LIBFB_C += $(newruntime)/libfb_intl_getweekdayname.o
LIBFB_C += $(newruntime)/libfb_io_lpos.o
LIBFB_C += $(newruntime)/libfb_io_lprint_byte.o
LIBFB_C += $(newruntime)/libfb_io_lprint_fix.o
LIBFB_C += $(newruntime)/libfb_io_lprint_fp.o
LIBFB_C += $(newruntime)/libfb_io_lprint_int.o
LIBFB_C += $(newruntime)/libfb_io_lprint_longint.o
LIBFB_C += $(newruntime)/libfb_io_lprint_short.o
LIBFB_C += $(newruntime)/libfb_io_lprint_str.o
LIBFB_C += $(newruntime)/libfb_io_lprintusg.o
LIBFB_C += $(newruntime)/libfb_io_lprintvoid.o
LIBFB_C += $(newruntime)/libfb_io_lprint_wstr.o
LIBFB_C += $(newruntime)/libfb_io_print_byte.o
LIBFB_C += $(newruntime)/libfb_io_print.o
LIBFB_C += $(newruntime)/libfb_io_print_fix.o
LIBFB_C += $(newruntime)/libfb_io_print_fp.o
LIBFB_C += $(newruntime)/libfb_io_print_int.o
LIBFB_C += $(newruntime)/libfb_io_print_longint.o
LIBFB_C += $(newruntime)/libfb_io_printpad.o
LIBFB_C += $(newruntime)/libfb_io_printpad_wstr.o
LIBFB_C += $(newruntime)/libfb_io_print_short.o
LIBFB_C += $(newruntime)/libfb_io_printusg.o
LIBFB_C += $(newruntime)/libfb_io_printvoid.o
LIBFB_C += $(newruntime)/libfb_io_printvoid_wstr.o
LIBFB_C += $(newruntime)/libfb_io_print_wstr.o
LIBFB_C += $(newruntime)/libfb_io_setpos.o
LIBFB_C += $(newruntime)/libfb_io_spc.o
LIBFB_C += $(newruntime)/libfb_io_view.o
LIBFB_C += $(newruntime)/libfb_io_viewhlp.o
LIBFB_C += $(newruntime)/libfb_io_widthdev.o
LIBFB_C += $(newruntime)/libfb_io_widthfile.o
LIBFB_C += $(newruntime)/libfb_io_writebyte.o
LIBFB_C += $(newruntime)/libfb_io_writefloat.o
LIBFB_C += $(newruntime)/libfb_io_writeint.o
LIBFB_C += $(newruntime)/libfb_io_writelongint.o
LIBFB_C += $(newruntime)/libfb_io_writeshort.o
LIBFB_C += $(newruntime)/libfb_io_writestr.o
LIBFB_C += $(newruntime)/libfb_io_writevoid.o
LIBFB_C += $(newruntime)/libfb_io_write_wstr.o
LIBFB_C += $(newruntime)/libfb_list.o
LIBFB_C += $(newruntime)/libfb_listdyn.o
LIBFB_C += $(newruntime)/libfb_math_fix.o
LIBFB_C += $(newruntime)/libfb_math_frac.o
LIBFB_C += $(newruntime)/libfb_math_rnd.o
LIBFB_C += $(newruntime)/libfb_math_sgn.o
LIBFB_C += $(newruntime)/libfb_mem_copyclear.o
LIBFB_C += $(newruntime)/libfb_qb_file_open.o
LIBFB_C += $(newruntime)/libfb_qb_inkey.o
LIBFB_C += $(newruntime)/libfb_qb_sleep.o
LIBFB_C += $(newruntime)/libfb_qb_str_convto.o
LIBFB_C += $(newruntime)/libfb_qb_str_convto_flt.o
LIBFB_C += $(newruntime)/libfb_qb_str_convto_lng.o
LIBFB_C += $(newruntime)/libfb_signals.o
LIBFB_C += $(newruntime)/libfb_str_asc.o
LIBFB_C += $(newruntime)/libfb_str_assign.o
LIBFB_C += $(newruntime)/libfb_str_base.o
LIBFB_C += $(newruntime)/libfb_str_bin.o
LIBFB_C += $(newruntime)/libfb_str_bin_lng.o
LIBFB_C += $(newruntime)/libfb_str_chr.o
LIBFB_C += $(newruntime)/libfb_str_comp.o
LIBFB_C += $(newruntime)/libfb_str_concatassign.o
LIBFB_C += $(newruntime)/libfb_str_concat.o
LIBFB_C += $(newruntime)/libfb_str_convfrom.o
LIBFB_C += $(newruntime)/libfb_str_convfrom_int.o
LIBFB_C += $(newruntime)/libfb_str_convfrom_lng.o
LIBFB_C += $(newruntime)/libfb_str_convfrom_rad.o
LIBFB_C += $(newruntime)/libfb_str_convfrom_radlng.o
LIBFB_C += $(newruntime)/libfb_str_convfrom_uint.o
LIBFB_C += $(newruntime)/libfb_str_convfrom_ulng.o
LIBFB_C += $(newruntime)/libfb_str_convto.o
LIBFB_C += $(newruntime)/libfb_str_convto_flt.o
LIBFB_C += $(newruntime)/libfb_str_convto_lng.o
LIBFB_C += $(newruntime)/libfb_str_core.o
LIBFB_C += $(newruntime)/libfb_str_cvmk.o
LIBFB_C += $(newruntime)/libfb_str_del.o
LIBFB_C += $(newruntime)/libfb_str_fill.o
LIBFB_C += $(newruntime)/libfb_str_format.o
LIBFB_C += $(newruntime)/libfb_str_ftoa.o
LIBFB_C += $(newruntime)/libfb_str_hex.o
LIBFB_C += $(newruntime)/libfb_str_hex_lng.o
LIBFB_C += $(newruntime)/libfb_str_instrany.o
LIBFB_C += $(newruntime)/libfb_str_instr.o
LIBFB_C += $(newruntime)/libfb_str_instrrevany.o
LIBFB_C += $(newruntime)/libfb_str_instrrev.o
LIBFB_C += $(newruntime)/libfb_str_lcase.o
LIBFB_C += $(newruntime)/libfb_str_left.o
LIBFB_C += $(newruntime)/libfb_str_len.o
LIBFB_C += $(newruntime)/libfb_str_ltrimany.o
LIBFB_C += $(newruntime)/libfb_str_ltrim.o
LIBFB_C += $(newruntime)/libfb_str_ltrimex.o
LIBFB_C += $(newruntime)/libfb_str_midassign.o
LIBFB_C += $(newruntime)/libfb_str_mid.o
LIBFB_C += $(newruntime)/libfb_str_misc.o
LIBFB_C += $(newruntime)/libfb_str_oct.o
LIBFB_C += $(newruntime)/libfb_str_oct_lng.o
LIBFB_C += $(newruntime)/libfb_str_right.o
LIBFB_C += $(newruntime)/libfb_str_rtrimany.o
LIBFB_C += $(newruntime)/libfb_str_rtrim.o
LIBFB_C += $(newruntime)/libfb_str_rtrimex.o
LIBFB_C += $(newruntime)/libfb_str_set.o
LIBFB_C += $(newruntime)/libfb_str_tempdescf.o
LIBFB_C += $(newruntime)/libfb_str_tempdescv.o
LIBFB_C += $(newruntime)/libfb_str_tempdescz.o
LIBFB_C += $(newruntime)/libfb_str_tempres.o
LIBFB_C += $(newruntime)/libfb_str_trimany.o
LIBFB_C += $(newruntime)/libfb_str_trim.o
LIBFB_C += $(newruntime)/libfb_str_trimex.o
LIBFB_C += $(newruntime)/libfb_str_ucase.o
LIBFB_C += $(newruntime)/libfb_strw_alloc.o
LIBFB_C += $(newruntime)/libfb_strw_asc.o
LIBFB_C += $(newruntime)/libfb_strw_assign.o
LIBFB_C += $(newruntime)/libfb_strw_bin.o
LIBFB_C += $(newruntime)/libfb_strw_bin_lng.o
LIBFB_C += $(newruntime)/libfb_strw_chr.o
LIBFB_C += $(newruntime)/libfb_strw_comp.o
LIBFB_C += $(newruntime)/libfb_strw_concatassign.o
LIBFB_C += $(newruntime)/libfb_strw_concat.o
LIBFB_C += $(newruntime)/libfb_strw_convassign.o
LIBFB_C += $(newruntime)/libfb_strw_convconcat.o
LIBFB_C += $(newruntime)/libfb_strw_convfrom.o
LIBFB_C += $(newruntime)/libfb_strw_convfrom_int.o
LIBFB_C += $(newruntime)/libfb_strw_convfrom_lng.o
LIBFB_C += $(newruntime)/libfb_strw_convfrom_rad.o
LIBFB_C += $(newruntime)/libfb_strw_convfrom_radlng.o
LIBFB_C += $(newruntime)/libfb_strw_convfrom_str.o
LIBFB_C += $(newruntime)/libfb_strw_convfrom_uint.o
LIBFB_C += $(newruntime)/libfb_strw_convfrom_ulng.o
LIBFB_C += $(newruntime)/libfb_strw_convto.o
LIBFB_C += $(newruntime)/libfb_strw_convto_flt.o
LIBFB_C += $(newruntime)/libfb_strw_convto_lng.o
LIBFB_C += $(newruntime)/libfb_strw_convto_str.o
LIBFB_C += $(newruntime)/libfb_strw_del.o
LIBFB_C += $(newruntime)/libfb_strw_fill.o
LIBFB_C += $(newruntime)/libfb_strw_ftoa.o
LIBFB_C += $(newruntime)/libfb_strw_hex.o
LIBFB_C += $(newruntime)/libfb_strw_hex_lng.o
LIBFB_C += $(newruntime)/libfb_strw_instrany.o
LIBFB_C += $(newruntime)/libfb_strw_instr.o
LIBFB_C += $(newruntime)/libfb_strw_instrrevany.o
LIBFB_C += $(newruntime)/libfb_strw_instrrev.o
LIBFB_C += $(newruntime)/libfb_strw_lcase.o
LIBFB_C += $(newruntime)/libfb_strw_left.o
LIBFB_C += $(newruntime)/libfb_strw_len.o
LIBFB_C += $(newruntime)/libfb_strw_ltrimany.o
LIBFB_C += $(newruntime)/libfb_strw_ltrim.o
LIBFB_C += $(newruntime)/libfb_strw_ltrimex.o
LIBFB_C += $(newruntime)/libfb_strw_midassign.o
LIBFB_C += $(newruntime)/libfb_strw_mid.o
LIBFB_C += $(newruntime)/libfb_strw_oct.o
LIBFB_C += $(newruntime)/libfb_strw_oct_lng.o
LIBFB_C += $(newruntime)/libfb_strw_right.o
LIBFB_C += $(newruntime)/libfb_strw_rtrimany.o
LIBFB_C += $(newruntime)/libfb_strw_rtrim.o
LIBFB_C += $(newruntime)/libfb_strw_rtrimex.o
LIBFB_C += $(newruntime)/libfb_strw_set.o
LIBFB_C += $(newruntime)/libfb_strw_space.o
LIBFB_C += $(newruntime)/libfb_strw_trimany.o
LIBFB_C += $(newruntime)/libfb_strw_trim.o
LIBFB_C += $(newruntime)/libfb_strw_trimex.o
LIBFB_C += $(newruntime)/libfb_strw_ucase.o
LIBFB_C += $(newruntime)/libfb_swap_mem.o
LIBFB_C += $(newruntime)/libfb_swap_str.o
LIBFB_C += $(newruntime)/libfb_swap_wstr.o
LIBFB_C += $(newruntime)/libfb_sys_beep.o
LIBFB_C += $(newruntime)/libfb_sys_cdir.o
LIBFB_C += $(newruntime)/libfb_sys_chain.o
LIBFB_C += $(newruntime)/libfb_sys_chdir.o
LIBFB_C += $(newruntime)/libfb_sys_cmd.o
LIBFB_C += $(newruntime)/libfb_sys_environ.o
LIBFB_C += $(newruntime)/libfb_sys_exec_core.o
LIBFB_C += $(newruntime)/libfb_sys_exepath.o
LIBFB_C += $(newruntime)/libfb_sys_mkdir.o
LIBFB_C += $(newruntime)/libfb_sys_rmdir.o
LIBFB_C += $(newruntime)/libfb_sys_run.o
LIBFB_C += $(newruntime)/libfb_thread_ctx.o
LIBFB_C += $(newruntime)/libfb_time_core.o
LIBFB_C += $(newruntime)/libfb_time_dateadd.o
LIBFB_C += $(newruntime)/libfb_time_date.o
LIBFB_C += $(newruntime)/libfb_time_datediff.o
LIBFB_C += $(newruntime)/libfb_time_datepart.o
LIBFB_C += $(newruntime)/libfb_time_dateserial.o
LIBFB_C += $(newruntime)/libfb_time_dateset.o
LIBFB_C += $(newruntime)/libfb_time_datevalue.o
LIBFB_C += $(newruntime)/libfb_time_decodeserdate.o
LIBFB_C += $(newruntime)/libfb_time_decodesertime.o
LIBFB_C += $(newruntime)/libfb_time_isdate.o
LIBFB_C += $(newruntime)/libfb_time_monthname.o
LIBFB_C += $(newruntime)/libfb_time_now.o
LIBFB_C += $(newruntime)/libfb_time_parsedate.o
LIBFB_C += $(newruntime)/libfb_time_parsedatetime.o
LIBFB_C += $(newruntime)/libfb_time_parsetime.o
LIBFB_C += $(newruntime)/libfb_time_sleepex.o
LIBFB_C += $(newruntime)/libfb_time_time.o
LIBFB_C += $(newruntime)/libfb_time_timeserial.o
LIBFB_C += $(newruntime)/libfb_time_timeset.o
LIBFB_C += $(newruntime)/libfb_time_timevalue.o
LIBFB_C += $(newruntime)/libfb_time_week.o
LIBFB_C += $(newruntime)/libfb_time_weekdayname.o
LIBFB_C += $(newruntime)/libfb_utf_convfrom_char.o
LIBFB_C += $(newruntime)/libfb_utf_convfrom_wchar.o
LIBFB_C += $(newruntime)/libfb_utf_convto_char.o
LIBFB_C += $(newruntime)/libfb_utf_convto_wchar.o
LIBFB_C += $(newruntime)/libfb_utf_core.o
LIBFB_C += $(newruntime)/libfb_vfs_open.o

LIBFB_S :=

LIBFBGFX_H := $(LIBFB_H)
LIBFBGFX_C :=

ifndef DISABLE_GFX
  LIBFBGFX_H += runtime/fb_gfx_data.h
  LIBFBGFX_H += runtime/fb_gfx_gl.h
  LIBFBGFX_H += runtime/fb_gfx.h
  LIBFBGFX_H += runtime/fb_gfx_lzw.h
  LIBFBGFX_H += runtime/gfxdata/inline.h

  LIBFBGFX_C += $(newruntime)/libfb_gfx_access.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_blitter.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_bload.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_box.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_bsave.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_circle.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_cls.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_color.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_control.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_core.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_data.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_draw.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_drawstring.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_driver_null.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_event.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_get.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_getmouse.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_image.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_image_convert.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_image_info.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_inkey.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_line.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_lineinp.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_lineinp_wstr.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_lzw.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_lzw_enc.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_multikey.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_page.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_paint.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_palette.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_paletteget.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_pmap.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_point.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_print.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_print_wstr.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_pset.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_put_add.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_put_alpha.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_put_and.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_put_blend.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_put.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_put_custom.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_put_or.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_put_preset.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_put_pset.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_put_trans.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_put_xor.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_readstr.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_readxy.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_screen.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_screeninfo.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_screenlist.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_setmouse.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_sleep.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_softcursor.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_stick.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_vars.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_vgaemu.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_view.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_vsync.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_width.o
  LIBFBGFX_C += $(newruntime)/libfb_gfx_window.o
endif

ifeq ($(TARGET_OS),dos)
  LIBFB_H += runtime/fb_dos.h
  LIBFB_H += runtime/fb_unicode_dos.h
  LIBFB_C += $(newruntime)/libfb_dev_pipe_close_dos.o
  LIBFB_C += $(newruntime)/libfb_dev_pipe_open_dos.o
  LIBFB_C += $(newruntime)/libfb_drv_file_copy_dos.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_dos.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_data_dos.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_get_dos.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_getdateformat_dos.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_getmonthname_dos.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_gettimeformat_dos.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_getweekdayname_dos.o
  LIBFB_C += $(newruntime)/libfb_farmemset_dos.o
  LIBFB_C += $(newruntime)/libfb_file_dir_dos.o
  LIBFB_C += $(newruntime)/libfb_file_hconvpath_dos.o
  LIBFB_C += $(newruntime)/libfb_file_hlock_dos.o
  LIBFB_C += $(newruntime)/libfb_file_resetex_dos.o
  LIBFB_C += $(newruntime)/libfb_hexit_dos.o
  LIBFB_C += $(newruntime)/libfb_hinit_dos.o
  LIBFB_C += $(newruntime)/libfb_hsignals_dos.o
  LIBFB_C += $(newruntime)/libfb_io_cls_dos.o
  LIBFB_C += $(newruntime)/libfb_io_color_dos.o
  LIBFB_C += $(newruntime)/libfb_io_getsize_dos.o
  LIBFB_C += $(newruntime)/libfb_io_inkey_dos.o
  LIBFB_C += $(newruntime)/libfb_io_isredir_dos.o
  LIBFB_C += $(newruntime)/libfb_io_locate_dos.o
  LIBFB_C += $(newruntime)/libfb_io_maxrow_dos.o
  LIBFB_C += $(newruntime)/libfb_io_mouse_dos.o
  LIBFB_C += $(newruntime)/libfb_io_multikey_dos.o
  LIBFB_C += $(newruntime)/libfb_io_pageset_dos.o
  LIBFB_C += $(newruntime)/libfb_io_pcopy_dos.o
  LIBFB_C += $(newruntime)/libfb_io_printbuff_dos.o
  LIBFB_C += $(newruntime)/libfb_io_printbuff_wstr_dos.o
  LIBFB_C += $(newruntime)/libfb_io_printer_dos.o
  LIBFB_C += $(newruntime)/libfb_io_readstr_dos.o
  LIBFB_C += $(newruntime)/libfb_io_scroll_dos.o
  LIBFB_C += $(newruntime)/libfb_io_serial_dos.o
  LIBFB_C += $(newruntime)/libfb_io_viewupdate_dos.o
  LIBFB_C += $(newruntime)/libfb_io_width_dos.o
  LIBFB_C += $(newruntime)/libfb_sys_exec_dos.o
  LIBFB_C += $(newruntime)/libfb_sys_fmem_dos.o
  LIBFB_C += $(newruntime)/libfb_sys_getcwd_dos.o
  LIBFB_C += $(newruntime)/libfb_sys_getexename_dos.o
  LIBFB_C += $(newruntime)/libfb_sys_getexepath_dos.o
  LIBFB_C += $(newruntime)/libfb_sys_getshortpath_dos.o
  LIBFB_C += $(newruntime)/libfb_sys_isr_dos.o
  LIBFB_C += $(newruntime)/libfb_sys_ports_dos.o
  LIBFB_C += $(newruntime)/libfb_sys_shell_dos.o
  LIBFB_C += $(newruntime)/libfb_sys_sleep_dos.o
  LIBFB_C += $(newruntime)/libfb_thread_cond_dos.o
  LIBFB_C += $(newruntime)/libfb_thread_core_dos.o
  LIBFB_C += $(newruntime)/libfb_thread_mutex_dos.o
  LIBFB_C += $(newruntime)/libfb_time_setdate_dos.o
  LIBFB_C += $(newruntime)/libfb_time_settime_dos.o
  LIBFB_C += $(newruntime)/libfb_time_sleep_dos.o
  LIBFB_C += $(newruntime)/libfb_time_tmr_dos.o
  LIBFB_S += $(newruntime)/libfb_drv_isr.o
  ifndef DISABLE_GFX
    LIBFBGFX_H += runtime/fb_gfx_dos.h
    LIBFBGFX_H += runtime/vesa.h
    LIBFBGFX_H += runtime/vga.h
    LIBFBGFX_C += $(newruntime)/libfb_gfx_dos.o
    LIBFBGFX_C += $(newruntime)/libfb_gfx_driver_bios_dos.o
    LIBFBGFX_C += $(newruntime)/libfb_gfx_driver_modex_dos.o
    LIBFBGFX_C += $(newruntime)/libfb_gfx_driver_vesa_bnk_dos.o
    LIBFBGFX_C += $(newruntime)/libfb_gfx_driver_vesa_lin_dos.o
    LIBFBGFX_C += $(newruntime)/libfb_gfx_driver_vga_dos.o
    LIBFBGFX_C += $(newruntime)/libfb_gfx_joystick_dos.o
    LIBFBGFX_C += $(newruntime)/libfb_gfx_vesa_core_dos.o
    LIBFBGFX_S += $(newruntime)/libfb_gfx_mouse_dos.o
    LIBFBGFX_S += $(newruntime)/libfb_gfx_vesa_dos.o
  endif
endif

ifeq ($(TARGET_OS),freebsd)
  LIBFB_C += $(newruntime)/libfb_hexit_freebsd.o
  LIBFB_C += $(newruntime)/libfb_hinit_freebsd.o
  LIBFB_C += $(newruntime)/libfb_io_mouse_freebsd.o
  LIBFB_C += $(newruntime)/libfb_io_multikey_freebsd.o
  LIBFB_C += $(newruntime)/libfb_sys_fmem_freebsd.o
  LIBFB_C += $(newruntime)/libfb_sys_getexename_freebsd.o
  LIBFB_C += $(newruntime)/libfb_sys_getexepath_freebsd.o
  ifndef DISABLE_GFX
    LIBFBGFX_C += $(newruntime)/libfb_gfx_freebsd.o
    LIBFBGFX_C += $(newruntime)/libfb_gfx_joystick_freebsd.o
  endif
endif

ifeq ($(TARGET_OS),linux)
  LIBFB_H += runtime/fb_gfx_linux.h
  LIBFB_H += runtime/fb_linux.h
  LIBFB_C += $(newruntime)/libfb_hexit_linux.o
  LIBFB_C += $(newruntime)/libfb_hinit_linux.o
  LIBFB_C += $(newruntime)/libfb_io_mouse_linux.o
  LIBFB_C += $(newruntime)/libfb_io_multikey_linux.o
  LIBFB_C += $(newruntime)/libfb_io_serial_linux.o
  LIBFB_C += $(newruntime)/libfb_sys_fmem_linux.o
  LIBFB_C += $(newruntime)/libfb_sys_getexename_linux.o
  LIBFB_C += $(newruntime)/libfb_sys_getexepath_linux.o
  LIBFB_C += $(newruntime)/libfb_sys_ports_linux.o
  ifndef DISABLE_GFX
    LIBFBGFX_H += runtime/fb_gfx_linux.h
    LIBFBGFX_C += $(newruntime)/libfb_gfx_driver_fbdev_linux.o
    LIBFBGFX_C += $(newruntime)/libfb_gfx_joystick_linux.o
    LIBFBGFX_C += $(newruntime)/libfb_gfx_linux.o
  endif
endif

ifeq ($(TARGET_OS),netbsd)
  LIBFB_C += $(newruntime)/libfb_hexit_netbsd.o
  LIBFB_C += $(newruntime)/libfb_hinit_netbsd.o
  LIBFB_C += $(newruntime)/libfb_io_mouse_netbsd.o
  LIBFB_C += $(newruntime)/libfb_io_multikey_netbsd.o
  LIBFB_C += $(newruntime)/libfb_sys_fmem_netbsd.o
  LIBFB_C += $(newruntime)/libfb_sys_getexename_netbsd.o
  LIBFB_C += $(newruntime)/libfb_sys_getexepath_netbsd.o
endif

ifeq ($(TARGET_OS),openbsd)
  LIBFB_C += $(newruntime)/libfb_hexit_openbsd.o
  LIBFB_C += $(newruntime)/libfb_hinit_openbsd.o
  LIBFB_C += $(newruntime)/libfb_io_mouse_openbsd.o
  LIBFB_C += $(newruntime)/libfb_io_multikey_openbsd.o
  LIBFB_C += $(newruntime)/libfb_sys_fmem_openbsd.o
  LIBFB_C += $(newruntime)/libfb_sys_getexename_openbsd.o
  LIBFB_C += $(newruntime)/libfb_sys_getexepath_openbsd.o
  LIBFB_C += $(newruntime)/swprintf_hack_openbsd.o
  ifndef DISABLE_GFX
    LIBFBGFX_C += $(newruntime)/libfb_gfx_joystick_openbsd.o
    LIBFBGFX_C += $(newruntime)/libfb_gfx_openbsd.o
  endif
endif

ifeq ($(TARGET_OS),xbox)
  LIBFB_H += runtime/fb_xbox.h
  LIBFB_C += $(newruntime)/libfb_dev_pipe_close_xbox.o
  LIBFB_C += $(newruntime)/libfb_dev_pipe_open_xbox.o
  LIBFB_C += $(newruntime)/libfb_drv_file_copy_xbox.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_get_xbox.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_getdateformat_xbox.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_getmonthname_xbox.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_gettimeformat_xbox.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_getweekdayname_xbox.o
  LIBFB_C += $(newruntime)/libfb_file_dir_xbox.o
  LIBFB_C += $(newruntime)/libfb_file_hconvpath_xbox.o
  LIBFB_C += $(newruntime)/libfb_file_hlock_xbox.o
  LIBFB_C += $(newruntime)/libfb_hexit_xbox.o
  LIBFB_C += $(newruntime)/libfb_hinit_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_cls_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_color_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_getsize_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_inkey_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_isredir_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_locate_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_maxrow_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_mouse_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_multikey_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_pageset_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_pcopy_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_printbuff_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_printbuff_wstr_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_printer_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_readstr_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_scroll_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_serial_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_viewupdate_xbox.o
  LIBFB_C += $(newruntime)/libfb_io_width_xbox.o
  LIBFB_C += $(newruntime)/libfb_sys_dylib_xbox.o
  LIBFB_C += $(newruntime)/libfb_sys_exec_xbox.o
  LIBFB_C += $(newruntime)/libfb_sys_fmem_xbox.o
  LIBFB_C += $(newruntime)/libfb_sys_getcwd_xbox.o
  LIBFB_C += $(newruntime)/libfb_sys_getexename_xbox.o
  LIBFB_C += $(newruntime)/libfb_sys_getexepath_xbox.o
  LIBFB_C += $(newruntime)/libfb_sys_getshortpath_xbox.o
  LIBFB_C += $(newruntime)/libfb_sys_shell_xbox.o
  LIBFB_C += $(newruntime)/libfb_sys_sleep_xbox.o
  LIBFB_C += $(newruntime)/libfb_thread_cond_xbox.o
  LIBFB_C += $(newruntime)/libfb_thread_core_xbox.o
  LIBFB_C += $(newruntime)/libfb_thread_mutex_xbox.o
  LIBFB_C += $(newruntime)/libfb_time_setdate_xbox.o
  LIBFB_C += $(newruntime)/libfb_time_settime_xbox.o
  LIBFB_C += $(newruntime)/libfb_time_sleep_xbox.o
  LIBFB_C += $(newruntime)/libfb_time_tmr_xbox.o
  LIBFB_S += $(newruntime)/libfb_alloca.o
  ifndef DISABLE_GFX
    LIBFBGFX_C += $(newruntime)/libfb_gfx_driver_xbox.o
  endif
endif

ifneq ($(filter darwin freebsd linux netbsd openbsd solaris,$(TARGET_OS)),)
  LIBFB_H += runtime/fb_unix.h
  LIBFB_C += $(newruntime)/libfb_dev_pipe_close_unix.o
  LIBFB_C += $(newruntime)/libfb_dev_pipe_open_unix.o
  LIBFB_C += $(newruntime)/libfb_drv_file_copy_unix.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_get_unix.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_getdateformat_unix.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_getmonthname_unix.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_gettimeformat_unix.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_getweekdayname_unix.o
  LIBFB_C += $(newruntime)/libfb_file_dir_unix.o
  LIBFB_C += $(newruntime)/libfb_file_hconvpath_unix.o
  LIBFB_C += $(newruntime)/libfb_file_hlock_unix.o
  LIBFB_C += $(newruntime)/libfb_file_resetex_unix.o
  LIBFB_C += $(newruntime)/libfb_hdynload_unix.o
  LIBFB_C += $(newruntime)/libfb_hexit_unix.o
  LIBFB_C += $(newruntime)/libfb_hinit_unix.o
  LIBFB_C += $(newruntime)/libfb_hsignals_unix.o
  LIBFB_C += $(newruntime)/libfb_io_cls_unix.o
  LIBFB_C += $(newruntime)/libfb_io_color_unix.o
  LIBFB_C += $(newruntime)/libfb_io_getsize_unix.o
  LIBFB_C += $(newruntime)/libfb_io_inkey_unix.o
  LIBFB_C += $(newruntime)/libfb_io_isredir_unix.o
  LIBFB_C += $(newruntime)/libfb_io_locate_unix.o
  LIBFB_C += $(newruntime)/libfb_io_maxrow_unix.o
  LIBFB_C += $(newruntime)/libfb_io_pageset_unix.o
  LIBFB_C += $(newruntime)/libfb_io_pcopy_unix.o
  LIBFB_C += $(newruntime)/libfb_io_printbuff_unix.o
  LIBFB_C += $(newruntime)/libfb_io_printbuff_wstr_unix.o
  LIBFB_C += $(newruntime)/libfb_io_printer_unix.o
  LIBFB_C += $(newruntime)/libfb_io_readstr_unix.o
  LIBFB_C += $(newruntime)/libfb_io_scroll_unix.o
  LIBFB_C += $(newruntime)/libfb_io_viewupdate_unix.o
  LIBFB_C += $(newruntime)/libfb_io_width_unix.o
  LIBFB_C += $(newruntime)/libfb_io_xfocus_unix.o
  LIBFB_C += $(newruntime)/libfb_scancodes_unix.o
  LIBFB_C += $(newruntime)/libfb_sys_delay_unix.o
  LIBFB_C += $(newruntime)/libfb_sys_dylib_unix.o
  LIBFB_C += $(newruntime)/libfb_sys_exec_unix.o
  LIBFB_C += $(newruntime)/libfb_sys_getcwd_unix.o
  LIBFB_C += $(newruntime)/libfb_sys_getshortpath_unix.o
  LIBFB_C += $(newruntime)/libfb_sys_shell_unix.o
  LIBFB_C += $(newruntime)/libfb_thread_cond_unix.o
  LIBFB_C += $(newruntime)/libfb_thread_core_unix.o
  LIBFB_C += $(newruntime)/libfb_thread_mutex_unix.o
  LIBFB_C += $(newruntime)/libfb_time_setdate_unix.o
  LIBFB_C += $(newruntime)/libfb_time_settime_unix.o
  LIBFB_C += $(newruntime)/libfb_time_sleep_unix.o
  LIBFB_C += $(newruntime)/libfb_time_tmr_unix.o
  ifndef DISABLE_GFX
    ifndef DISABLE_X
      LIBFBGFX_H += runtime/fb_gfx_x11.h
      LIBFBGFX_C += $(newruntime)/libfb_gfx_driver_x11.o
      LIBFBGFX_C += $(newruntime)/libfb_gfx_x11.o
      ifndef DISABLE_OPENGL
        LIBFBGFX_C += $(newruntime)/libfb_gfx_driver_opengl_x11.o
      endif
    endif
  endif
endif

ifneq ($(filter cygwin win32,$(TARGET_OS)),)
  LIBFB_H += runtime/fb_unicode_win32.h
  LIBFB_H += runtime/fb_win32.h
  LIBFB_H += runtime/fbportio/fbportio.h
  LIBFB_H += runtime/fbportio/inline.h
  LIBFB_C += $(newruntime)/libfb_dev_pipe_close_win32.o
  LIBFB_C += $(newruntime)/libfb_dev_pipe_open_win32.o
  LIBFB_C += $(newruntime)/libfb_drv_file_copy_win32.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_get_win32.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_getdateformat_win32.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_getmonthname_win32.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_gettimeformat_win32.o
  LIBFB_C += $(newruntime)/libfb_drv_intl_getweekdayname_win32.o
  LIBFB_C += $(newruntime)/libfb_file_dir_win32.o
  LIBFB_C += $(newruntime)/libfb_file_hconvpath_win32.o
  LIBFB_C += $(newruntime)/libfb_file_hlock_win32.o
  LIBFB_C += $(newruntime)/libfb_file_resetex_win32.o
  LIBFB_C += $(newruntime)/libfb_hdynload_win32.o
  LIBFB_C += $(newruntime)/libfb_hexit_win32.o
  LIBFB_C += $(newruntime)/libfb_hinit_win32.o
  LIBFB_C += $(newruntime)/libfb_hsignals_win32.o
  LIBFB_C += $(newruntime)/libfb_intl_conv_win32.o
  LIBFB_C += $(newruntime)/libfb_intl_win32.o
  LIBFB_C += $(newruntime)/libfb_io_cls_win32.o
  LIBFB_C += $(newruntime)/libfb_io_clsex_win32.o
  LIBFB_C += $(newruntime)/libfb_io_color_win32.o
  LIBFB_C += $(newruntime)/libfb_io_colorget_win32.o
  LIBFB_C += $(newruntime)/libfb_io_gethnd_win32.o
  LIBFB_C += $(newruntime)/libfb_io_getsize_win32.o
  LIBFB_C += $(newruntime)/libfb_io_getwindow_win32.o
  LIBFB_C += $(newruntime)/libfb_io_getwindowex_win32.o
  LIBFB_C += $(newruntime)/libfb_io_getx_win32.o
  LIBFB_C += $(newruntime)/libfb_io_getxy_win32.o
  LIBFB_C += $(newruntime)/libfb_io_gety_win32.o
  LIBFB_C += $(newruntime)/libfb_io_inkey_win32.o
  LIBFB_C += $(newruntime)/libfb_io_input_win32.o
  LIBFB_C += $(newruntime)/libfb_io_isredir_win32.o
  LIBFB_C += $(newruntime)/libfb_io_locate_win32.o
  LIBFB_C += $(newruntime)/libfb_io_locateex_win32.o
  LIBFB_C += $(newruntime)/libfb_io_maxrow_win32.o
  LIBFB_C += $(newruntime)/libfb_io_mouse_win32.o
  LIBFB_C += $(newruntime)/libfb_io_multikey_win32.o
  LIBFB_C += $(newruntime)/libfb_io_pageset_win32.o
  LIBFB_C += $(newruntime)/libfb_io_pcopy_win32.o
  LIBFB_C += $(newruntime)/libfb_io_printbuff_win32.o
  LIBFB_C += $(newruntime)/libfb_io_printbuff_wstr_win32.o
  LIBFB_C += $(newruntime)/libfb_io_printer_win32.o
  LIBFB_C += $(newruntime)/libfb_io_readstr_win32.o
  LIBFB_C += $(newruntime)/libfb_io_readxy_win32.o
  LIBFB_C += $(newruntime)/libfb_io_screensize_win32.o
  LIBFB_C += $(newruntime)/libfb_io_scroll_win32.o
  LIBFB_C += $(newruntime)/libfb_io_scrollex_win32.o
  LIBFB_C += $(newruntime)/libfb_io_serial_win32.o
  LIBFB_C += $(newruntime)/libfb_io_viewupdate_win32.o
  LIBFB_C += $(newruntime)/libfb_io_width_win32.o
  LIBFB_C += $(newruntime)/libfb_io_window_win32.o
  LIBFB_C += $(newruntime)/libfb_sys_dylib_win32.o
  LIBFB_C += $(newruntime)/libfb_sys_exec_win32.o
  LIBFB_C += $(newruntime)/libfb_sys_fmem_win32.o
  LIBFB_C += $(newruntime)/libfb_sys_getcwd_win32.o
  LIBFB_C += $(newruntime)/libfb_sys_getexename_win32.o
  LIBFB_C += $(newruntime)/libfb_sys_getexepath_win32.o
  LIBFB_C += $(newruntime)/libfb_sys_getshortpath_win32.o
  LIBFB_C += $(newruntime)/libfb_sys_ports_win32.o
  LIBFB_C += $(newruntime)/libfb_sys_shell_win32.o
  LIBFB_C += $(newruntime)/libfb_sys_sleep_win32.o
  LIBFB_C += $(newruntime)/libfb_thread_cond_win32.o
  LIBFB_C += $(newruntime)/libfb_thread_core_win32.o
  LIBFB_C += $(newruntime)/libfb_thread_mutex_win32.o
  LIBFB_C += $(newruntime)/libfb_time_setdate_win32.o
  LIBFB_C += $(newruntime)/libfb_time_settime_win32.o
  LIBFB_C += $(newruntime)/libfb_time_sleep_win32.o
  LIBFB_C += $(newruntime)/libfb_time_tmr_win32.o
  LIBFB_S += $(newruntime)/libfb_alloca.o
  ifndef DISABLE_GFX
    LIBFBGFX_H += runtime/fb_gfx_win32.h
    LIBFBGFX_C += $(newruntime)/libfb_gfx_driver_ddraw_win32.o
    LIBFBGFX_C += $(newruntime)/libfb_gfx_driver_gdi_win32.o
    LIBFBGFX_C += $(newruntime)/libfb_gfx_joystick_win32.o
    LIBFBGFX_C += $(newruntime)/libfb_gfx_win32.o
    ifndef DISABLE_OPENGL
      LIBFBGFX_C += $(newruntime)/libfb_gfx_driver_opengl_win32.o
    endif
  endif
endif

ifneq ($(filter 386 486 586 686,$(TARGET_ARCH)),)
  LIBFB_H += runtime/fb_x86.h
  LIBFB_S += $(newruntime)/libfb_cpudetect_x86.o
  ifndef DISABLE_GFX
    LIBFBGFX_H += runtime/fb_gfx_mmx.h
    LIBFBGFX_S += $(newruntime)/libfb_gfx_blitter_mmx.o
    LIBFBGFX_S += $(newruntime)/libfb_gfx_mmx.o
    LIBFBGFX_S += $(newruntime)/libfb_gfx_put_add_mmx.o
    LIBFBGFX_S += $(newruntime)/libfb_gfx_put_alpha_mmx.o
    LIBFBGFX_S += $(newruntime)/libfb_gfx_put_and_mmx.o
    LIBFBGFX_S += $(newruntime)/libfb_gfx_put_blend_mmx.o
    LIBFBGFX_S += $(newruntime)/libfb_gfx_put_or_mmx.o
    LIBFBGFX_S += $(newruntime)/libfb_gfx_put_preset_mmx.o
    LIBFBGFX_S += $(newruntime)/libfb_gfx_put_pset_mmx.o
    LIBFBGFX_S += $(newruntime)/libfb_gfx_put_trans_mmx.o
    LIBFBGFX_S += $(newruntime)/libfb_gfx_put_xor_mmx.o
  endif
endif

ifndef DISABLE_MT
  LIBFBMT_C := $(patsubst %.o,%.mt.o,$(LIBFB_C))
  LIBFBMT_S := $(patsubst %.o,%.mt.o,$(LIBFB_S))
endif

#
# Build rules
#
# Note: We're linking/ar'ing in uglier ways than would normally be necessary,
# in order to work around command line length limits, especially with DJGPP.
#
# This is needed for the runtime, because it consists of tons of objects, and
# with file names like new/runtime/libfb_foo_bar.o, the ar command line gets
# *really* long (14.5k chars), causing it (or *something*) to fail.
# (Windows XP cmd.exe -> DJGPP make.exe -> COMMAND.COM? -> DJGPP ar.exe)
#
# To get shorter file names we cd into new/runtime and run the ar command from
# there. That reduces the line to 9.3k chars.
#
# The "cd ../.."s are there because (for some reason I haven't figured out)
# cds in recipes change the curdir of the whole DJGPP make process. Normally
# each line in a recipe should be executed in its own shell, but in the DJGPP
# case something must be wrong, maybe the old 3.79.1 make is too buggish.
#

# We don't want to use any of make's built-in suffixes/rules
.SUFFIXES:

ifndef V
  QUIET_GEN   = @echo "GEN $@";
  QUIET_FBC   = @echo "FBC $@";
  QUIET_LINK  = @echo "LINK $@";
  QUIET_CC    = @echo "CC $@";
  QUIET_CPPAS = @echo "CPPAS $@";
  QUIET_AR    = @echo "AR $@";
endif

.PHONY: all
all: compiler runtime

.PHONY: compiler
compiler: $(newcompiler) $(newbin) $(FBC_NEW)

$(FBC_NEW): $(FBC_BAS) $(FBC_COBJINFO)
	$(QUIET_LINK)cd $(newcompiler); $(HOST_FBC) $(FBLFLAGS) $(patsubst $(newcompiler)/%,%,$^) -x ../../$@; cd ../..
#	$(QUIET_LINK)$(HOST_FBC) $(FBLFLAGS) $^ -x $@

$(FBC_BAS): $(newcompiler)/%.o: compiler/%.bas $(FBC_BI)
	$(QUIET_FBC)$(HOST_FBC) $(FBCFLAGS) -c $< -o $@

$(newcompiler)/c-objinfo.o: compiler/c-objinfo.c
	$(QUIET_CC)$(HOST_CC) -Wfatal-errors -Wall -c $< -o $@

$(FBC_CONFIG): compiler/config.bi.in
	$(QUIET_GEN)cp $< $@
  # The compiler expects the TARGET_* define for the default target.
  ifeq ($(TARGET_OS),cygwin)
	@echo '#define TARGET_CYGWIN' >> $@
  endif
  ifeq ($(TARGET_OS),darwin)
	@echo '#define TARGET_DARWIN' >> $@
  endif
  ifeq ($(TARGET_OS),dos)
	@echo '#define TARGET_DOS' >> $@
  endif
  ifeq ($(TARGET_OS),freebsd)
	@echo '#define TARGET_FREEBSD' >> $@
  endif
  ifeq ($(TARGET_OS),linux)
	@echo '#define TARGET_LINUX' >> $@
  endif
  ifeq ($(TARGET_OS),netbsd)
	@echo '#define TARGET_NETBSD' >> $@
  endif
  ifeq ($(TARGET_OS),openbsd)
	@echo '#define TARGET_OPENBSD' >> $@
  endif
  ifeq ($(TARGET_OS),win32)
	@echo '#define TARGET_WIN32' >> $@
  endif
  ifeq ($(TARGET_OS),xbox)
	@echo '#define TARGET_XBOX' >> $@
  endif
  # arch
  ifneq ($(filter 386 486 586 686,$(TARGET_ARCH)),)
	@echo '#define TARGET_X86' >> $@
  endif
  ifeq ($(TARGET_ARCH),x86_64)
	@echo '#define TARGET_X86_64' >> $@
  endif
  # The compiler expects ENABLE_* defines for all the targets that
  # should be compiled in, including the default target.
  ifdef ENABLE_CYGWIN
	@echo '#define ENABLE_CYGWIN "$(TRIPLET_CYGWIN)"' >> $@
  endif
  ifdef ENABLE_DARWIN
	@echo '#define ENABLE_DARWIN "$(TRIPLET_DARWIN)"' >> $@
  endif
  ifdef ENABLE_DOS
	@echo '#define ENABLE_DOS "$(TRIPLET_DOS)"' >> $@
  endif
  ifdef ENABLE_FREEBSD
	@echo '#define ENABLE_FREEBSD "$(TRIPLET_FREEBSD)"' >> $@
  endif
  ifdef ENABLE_LINUX
	@echo '#define ENABLE_LINUX "$(TRIPLET_LINUX)"' >> $@
  endif
  ifdef ENABLE_NETBSD
	@echo '#define ENABLE_NETBSD "$(TRIPLET_NETBSD)"' >> $@
  endif
  ifdef ENABLE_OPENBSD
	@echo '#define ENABLE_OPENBSD "$(TRIPLET_OPENBSD)"' >> $@
  endif
  ifdef ENABLE_WIN32
	@echo '#define ENABLE_WIN32 "$(TRIPLET_WIN32)"' >> $@
  endif
  ifdef ENABLE_XBOX
	@echo '#define ENABLE_XBOX "$(TRIPLET_XBOX)"' >> $@
  endif
  # Configuration
  ifdef ENABLE_FBBFD
	@echo '#define ENABLE_FBBFD $(ENABLE_FBBFD)' >> $@
  endif
  ifdef DISABLE_OBJINFO
	@echo '#define DISABLE_OBJINFO' >> $@
  endif
  ifdef ENABLE_PREFIX
	@echo '#define ENABLE_PREFIX "$(prefix)"' >> $@
  endif
  ifdef ENABLE_STANDALONE
	@echo '#define ENABLE_STANDALONE' >> $@
  endif
	@echo '#define FB_SUFFIX "$(SUFFIX)"' >> $@

.PHONY: runtime
runtime: $(newruntime) $(newlib) \
         $(FBRT0_NEW) $(LIBFB_NEW) $(LIBFBMT_NEW) $(LIBFBGFX_NEW)

$(FBRT0_NEW): runtime/fbrt0.c $(LIBFB_H)
	$(QUIET_CC)$(TARGET_CC) $(ALLCFLAGS) -c $< -o $@

$(LIBFB_NEW): $(LIBFB_C) $(LIBFB_S)
	$(QUIET_AR)cd $(newruntime); $(TARGET_AR) rcs ../../$@ $(patsubst $(newruntime)/%,%,$^); cd ../..
#	$(QUIET_AR)$(TARGET_AR) rcs $@ $^

$(LIBFBMT_NEW): $(LIBFBMT_C) $(LIBFBMT_S)
	$(QUIET_AR)cd $(newruntime); $(TARGET_AR) rcs ../../$@ $(patsubst $(newruntime)/%,%,$^); cd ../..
#	$(QUIET_AR)$(TARGET_AR) rcs $@ $^

$(LIBFBGFX_NEW): $(LIBFBGFX_C) $(LIBFBGFX_S)
	$(QUIET_AR)cd $(newruntime); $(TARGET_AR) rcs ../../$@ $(patsubst $(newruntime)/%,%,$^); cd ../..
#	$(QUIET_AR)$(TARGET_AR) rcs $@ $^

$(LIBFB_C): $(newruntime)/%.o: runtime/%.c $(LIBFB_H)
	$(QUIET_CC)$(TARGET_CC) $(ALLCFLAGS) -c $< -o $@

$(LIBFB_S): $(newruntime)/%.o: runtime/%.s $(LIBFB_H)
	$(QUIET_CPPAS)$(TARGET_CC) -x assembler-with-cpp $(ALLCFLAGS) -c $< -o $@

$(LIBFBMT_C): $(newruntime)/%.mt.o: runtime/%.c $(LIBFB_H)
	$(QUIET_CC)$(TARGET_CC) -DENABLE_MT $(ALLCFLAGS) -c $< -o $@

$(LIBFBMT_S): $(newruntime)/%.mt.o: runtime/%.s $(LIBFB_H)
	$(QUIET_CPPAS)$(TARGET_CC) -x assembler-with-cpp -DENABLE_MT $(ALLCFLAGS) -c $< -o $@

$(LIBFBGFX_C): $(newruntime)/%.o: runtime/%.c $(LIBFBGFX_H)
	$(QUIET_CC)$(TARGET_CC) $(ALLCFLAGS) -c $< -o $@

$(LIBFBGFX_S): $(newruntime)/%.o: runtime/%.s $(LIBFBGFX_H)
	$(QUIET_CPPAS)$(TARGET_CC) -x assembler-with-cpp $(ALLCFLAGS) -c $< -o $@

$(LIBFB_CONFIG): runtime/config.h.in
	$(QUIET_GEN)cp $< $@
  # The runtime expects the HOST_* defines for the system it's supposed to run on.
  # Note that we compile only one runtime: the one for the compiler's default
  # target.
  ifeq ($(TARGET_OS),cygwin)
	@echo '#define HOST_CYGWIN' >> $@
  endif
  ifeq ($(TARGET_OS),darwin)
	@echo '#define HOST_DARWIN' >> $@
  endif
  ifeq ($(TARGET_OS),dos)
	@echo '#define HOST_DOS' >> $@
  endif
  ifeq ($(TARGET_OS),freebsd)
	@echo '#define HOST_FREEBSD' >> $@
  endif
  ifeq ($(TARGET_OS),linux)
	@echo '#define HOST_LINUX' >> $@
  endif
  ifeq ($(TARGET_OS),win32)
	@echo '#define HOST_MINGW' >> $@
  endif
  ifeq ($(TARGET_OS),netbsd)
	@echo '#define HOST_NETBSD' >> $@
  endif
  ifeq ($(TARGET_OS),openbsd)
	@echo '#define HOST_OPENBSD' >> $@
  endif
  ifeq ($(TARGET_OS),solaris)
	@echo '#define HOST_SOLARIS' >> $@
  endif
  ifeq ($(TARGET_OS),xbox)
	@echo '#define HOST_XBOX' >> $@
  endif
  # OS family
  ifneq ($(filter darwin freebsd linux netbsd openbsd solaris,$(TARGET_OS)),)
	@echo '#define HOST_UNIX' >> $@
  endif
  ifneq ($(filter cygwin win32,$(TARGET_OS)),)
	@echo '#define HOST_WIN32' >> $@
  endif
  # arch
  ifneq ($(filter 386 486 586 686,$(TARGET_ARCH)),)
	@echo '#define HOST_X86' >> $@
  endif
  ifeq ($(TARGET_ARCH),x86_64)
	@echo '#define HOST_X86_64' >> $@
  endif
  ifeq ($(TARGET_ARCH),sparc)
	@echo '#define HOST_SPARC' >> $@
  endif
  ifeq ($(TARGET_ARCH),sparc64)
	@echo '#define HOST_SPARC64' >> $@
  endif
  ifeq ($(TARGET_ARCH),powerpc64)
	@echo '#define HOST_POWERPC64' >> $@
  endif
  # Configuration
  ifdef DISABLE_OPENGL
	@echo '#define DISABLE_OPENGL' >> $@
  endif
  ifdef DISABLE_X
	@echo '#define DISABLE_X' >> $@
  endif

.PHONY: install
install: install-compiler install-runtime

.PHONY: install-compiler
install-compiler: $(prefixbin) $(FBC_NEW)
	cp $(FBC_NEW) $(prefixbin)

.PHONY: install-runtime
install-runtime: $(prefixlib) \
                 $(FBRT0_NEW) $(LIBFB_NEW) $(LIBFBMT_NEW) $(LIBFBGFX_NEW)
	cp $(FBRT0_NEW) $(LIBFB_NEW) $(LIBFBMT_NEW) $(LIBFBGFX_NEW) $(prefixlib)

.PHONY: uninstall
uninstall: uninstall-compiler uninstall-runtime

.PHONY: uninstall-compiler
uninstall-compiler:
	rm -f $(FBC_PREFIX)

.PHONY: uninstall-runtime
uninstall-runtime:
	rm -f $(FBRT0_PREFIX) $(LIBFB_PREFIX) $(LIBFBMT_PREFIX) $(LIBFBGFX_PREFIX)
# Remove the lib/freebasic/ dir, unless we're standalone and it's just lib/
ifndef ENABLE_STANDALONE
	-rmdir $(prefixlib)
endif

$(newbin) $(newcompiler) $(newlib) $(newruntime) $(prefixbin) $(prefixlib):
	mkdir -p $@

.PHONY: clean
clean: clean-compiler clean-runtime

.PHONY: clean-compiler
clean-compiler:
	rm -f $(FBC_NEW) $(FBC_CONFIG) $(newcompiler)/*.o
	-rmdir -p $(newcompiler) $(newbin)

.PHONY: clean-runtime
clean-runtime:
	rm -f $(FBRT0_NEW) $(LIBFB_NEW) $(LIBFBMT_NEW) $(LIBFBGFX_NEW) $(LIBFB_CONFIG) $(newruntime)/*.o
	-rmdir -p $(newruntime) $(newlib)

.PHONY: help
help:
	@echo "Available commands:"
	@echo "  <none>|all                     to build compiler and runtime."
	@echo "  compiler                       (compiler only)"
	@echo "  runtime                        (runtime only)"
	@echo "  clean[-compiler|-runtime]      to remove built files."
	@echo "  install[-compiler|-runtime]    to install into prefix."
	@echo "  uninstall[-compiler|-runtime]  to remove from prefix."
	@echo "Variables:"
	@echo "  FBFLAGS ('-g'), CFLAGS ('-g -O2')"
	@echo "  new     The build directory ('new'); change this to differentiate multiple"
	@echo "          builds in one source tree."
	@echo "  prefix  The install directory ('.' on Windows/DOS; '/usr/local' elsewhere)"
	@echo "  HOST    A GNU triplet to cross-compile an fbc that will run on HOST."
	@echo "  TARGET  A GNU triplet to build a cross-fbc that produces for TARGET,"
	@echo "          and to cross-compile the runtime to run on TARGET."
	@echo "  SUFFIX  A string to append to the fbc program name and the lib/freebasic/"
	@echo "          directory, distinguishing this build from other installed versions."
	@echo "  FBC     The 'fbc', 'gcc', 'ar' tools to use. Note: When cross-compiling,"
	@echo "  CC      these cannot contain paths, because the host/target triplets will"
	@echo "  AR      be prepended. However, you can always set those variables directly:"
	@echo "          HOST_FBC, HOST_CC, TARGET_AR, TARGET_CC"
	@echo "  V       For verbose command lines"
	@echo "FreeBASIC configuration options:"
	@echo "  ENABLE_FBBFD=217  To use the FB headers for this exact libbfd version,"
	@echo "                    instead of using the system's bfd.h via a C wrapper."
	@echo "  DISABLE_OBJINFO   To disable fbc's objinfo feature and not use libbfd"
	@echo "  DISABLE_MT        Don't build libfbmt (auto-defined for DOS runtime)"
	@echo "  DISABLE_GFX       Don't build libfbgfx"
	@echo "  DISABLE_OPENGL    For libfbgfx without OpenGL support (Unix/Windows)"
	@echo "  DISABLE_X         For libfbgfx without X support (Unix)"
	@echo "  ENABLE_PREFIX     Hard-code the PREFIX into the compiler, instead of"
	@echo "                    building a relocatable compiler."
	@echo "  ENABLE_STANDALONE Use a simpler directory layout that places fbc into the"
	@echo "                    toplevel directory (instead of bin/) and does not use"
	@echo "                    freebasic/ sub-directories in include/ and lib/."
	@echo "                    (intended for self-contained installations)"
	@echo "  ENABLE_<TARGET>   For building a multi-target compiler. The ENABLE_* for"
	@echo "                    the default TARGET will automatically be defined."
	@echo "  TRIPLET_<TARGET>=<default-triplet>  For enabled targets, the compiler will"
	@echo "                    use the triplets to find binutils/libraries, unless the"
	@echo "                    user gave another one via the -target option. The triplet"
	@echo "                    for the default TARGET will automatically be defined."
	@echo "This makefile #includes config.mk and new/config.mk, allowing you to use them"
	@echo "to set variables in a more permanent and even build-directory specific way."
