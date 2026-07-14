TARGET 						= rk-ota
BUILD_MODE 					?= release

# uniq is a function which remove duplicate elements from a list
uniq = $(strip $(if $1,$(firstword $1) \
       $(call uniq,$(filter-out $(firstword $1),$1))))
       

OBJ_DIR = .build
EXE_DIR = .build
LST_DIR = .build
  
OUTPUT_DIR = ./

LINUXCS    ?= /usr

RMDIRS     := rm -rf
RMFILES    := rm -rf
MKDIR      := mkdir -p
ALLFILES   := /*.*
NULLDEVICE := /dev/null
SHELLNAMES := $(ComSpec)$(COMSPEC)
PATHSEP    := /

# Command output is hidden by default, it can be enabled by
# setting VERBOSE=true on the commandline.
ifeq ($(V),)
  ECHO = @
endif

# Try autodetecting the environment
ifeq ($(SHELLNAMES),)
  # Assume we are making on a Linux platform
  TOOLDIR ?= $(LINUXCS)
else
  QUOTE :="
  ifneq ($(COMSPEC),)
    # Assume we are making on a mingw/msys/cygwin platform running on Windows
    # This is a convenient place to override TOOLDIR, DO NOT add trailing
    # whitespace chars, they do matter !
    TOOLDIR ?= $(PROGRAMFILES)/$(WINDOWSCS)
    ifeq ($(findstring cygdrive,$(shell set)),)
      # We were not on a cygwin platform
      NULLDEVICE := NUL
    endif
  else
    # Assume we are making on a Windows platform
    # This is a convenient place to override TOOLDIR, DO NOT add trailing
    # whitespace chars, they do matter !
    SHELL      := $(SHELLNAMES)
    TOOLDIR    ?= $(ProgramFiles)/$(WINDOWSCS)
    RMDIRS     := rd /s /q
    RMFILES    := del /s /q
    MKDIR      := mkdir
    ALLFILES   := \*.*
    NULLDEVICE := NUL
    PATHSEP    := \\
  endif
endif

# Create directories and do a clean which is compatible with parallell make
$(shell $(MKDIR) $(subst /,$(PATHSEP),$(OBJ_DIR))>$(NULLDEVICE) 2>&1)
$( $(MKDIR) $(subst /,$(PATHSEP),$(EXE_DIR))>$(NULLDEVICE) 2>&1)
$(shell $(MKDIR) $(subst /,$(PATHSEP),$(LST_DIR))>$(NULLDEVICE) 2>&1)
ifeq (clean,$(findstring clean, $(MAKECMDGOALS)))
  ifneq ($(filter $(MAKECMDGOALS),all debug release),)
    $(shell $(RMFILES) $(subst /,$(PATHSEP),$(OBJ_DIR)$(ALLFILES))>$(NULLDEVICE) 2>&1)
    $(shell $(RMFILES) $(subst /,$(PATHSEP),$(EXE_DIR)$(ALLFILES))>$(NULLDEVICE) 2>&1)
    $(shell $(RMFILES) $(subst /,$(PATHSEP),$(LST_DIR)$(ALLFILES))>$(NULLDEVICE) 2>&1)
  endif
endif

#export CC	= gcc
#export CXX	= g++
#export LD	= ld
#export AR	= ar
#export OBJCOPY	= objcopy
#export OBJDUMP	= objdump

DEPFLAGS = -MMD -MP -MF $(@:.o=.d)

################################
######	External libraris
################################

EXTLIBS :=	
EXTINCLUDES :=	

################################
######	Libraris
################################

LIBS += -L/usr/local/lib -lssl -lcrypto -lz

################################
######	Main flags
################################

VERSION_DEFS = 
VERSION_DEFS += -DVERSION_MAJOR="$(VERSION_MAJOR)"
VERSION_DEFS += -DVERSION_MINOR="$(VERSION_MINOR)"
VERSION_DEFS += -DVERSION_BUILD_NUMBER="$(VERSION_BUILD_NUMBER)"
VERSION_DEFS += -DVERSION_HASH='"$(VERSION_HASH)"'

ifeq ($(BUILD_MODE), release)
BUILD_MODE_FLAGS   += -DNDEBUG -O0
else
BUILD_MODE_FLAGS   += -DDEBUG -Wno-implicit-fallthrough -O0 -g
endif

COMMON_FLAGS += -Wall -Wextra -Wno-deprecated-declarations -ffunction-sections -fno-jump-tables -fdata-sections

CFLAGS   += $(COMMON_FLAGS) $(DEPFLAGS) $(VERSION_DEFS) $(BUILD_MODE_FLAGS)
CXXFLAGS += $(COMMON_FLAGS) -fomit-frame-pointer $(DEPFLAGS) $(VERSION_DEFS) $(BUILD_MODE_FLAGS)
LDFLAGS  += -Wl,--gc-sections

CFLAGS   += -DSUCCESSFUL_BOOT=1
CXXFLAGS += -DSUCCESSFUL_BOOT=1

################################
######	Include paths
################################

INCLUDEPATHS += $(EXTINCLUDES)
INCLUDEPATHS += ./

################################
######	Main sources
################################

C_CXX_SRC += main.cpp
C_CXX_SRC += bootloader.cpp
C_CXX_SRC += md5sum.cpp
C_CXX_SRC += mtdutils.c

################################
######	
################################

INCLUDES = ${addprefix -I,$(INCLUDEPATHS)}

C_SRC = $(filter %.c, $(C_CXX_SRC))
CXX_SRC = $(filter %.cpp, $(C_CXX_SRC))

####################################################################
# Rules                                                            #
####################################################################

C_FILES = $(C_SRC)
CXX_FILES = $(CXX_SRC)
S_FILES = $(S_SRC)
s_FILES = $(s_SRC)
#make list of source paths, uniq removes duplicate paths
C_PATHS = $(call uniq, $(dir $(C_SRC) ) )
CXX_PATHS = $(call uniq, $(dir $(CXX_SRC) ) )
S_PATHS = $(call uniq, $(dir $(S_SRC) $(s_SRC) ) )

C_OBJS = $(addprefix $(OBJ_DIR)/, $(C_FILES:.c=.o))
CXX_OBJS = $(addprefix $(OBJ_DIR)/, $(CXX_FILES:.cpp=.o))
S_OBJS = $(if $(S_SRC), $(addprefix $(OBJ_DIR)/, $(S_FILES:.S=.o)))
s_OBJS = $(if $(s_SRC), $(addprefix $(OBJ_DIR)/, $(s_FILES:.s=.o)))
C_DEPS = $(addprefix $(OBJ_DIR)/, $(C_FILES:.c=.d))
CXX_DEPS = $(addprefix $(OBJ_DIR)/, $(CXX_FILES:.cpp=.d))
S_DEPS = $(addprefix $(OBJ_DIR)/, $(S_FILES:.S=.d))
s_DEPS = $(addprefix $(OBJ_DIR)/, $(s_FILES:.s=.d))
OBJS = $(C_OBJS) $(CXX_OBJS) $(S_OBJS) $(s_OBJS)

vpath %.c $(C_PATHS)
vpath %.cpp $(CXX_PATHS)
vpath %.s $(S_PATHS)
vpath %.S $(S_PATHS)

all:    $(TARGET)
debug:	$(TARGET)
release:$(TARGET)


# Create objects from C SRC files
$(OBJ_DIR)/%.o: %.c
	@echo "Building C file: $<"
	@mkdir -p $(dir $@)
	$(ECHO)$(CC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

# Create objects from CXX SRC files
$(OBJ_DIR)/%.o: %.cpp
	@echo "Building CPP file: $<"
	@mkdir -p $(dir $@)
	$(ECHO)$(CXX) $(CXXFLAGS) $(INCLUDES) -c -o $@ $<
	
$(OBJ_DIR):
	@mkdir -p $@	

# Dependdencies
#$(OBJ_DIR)/$(PROJ_NAME).elf: $(OBJS) | $(OBJ_DIR)
	
# Link
$(TARGET): $(OBJS) $(EXTLIBS)
	@echo "Linking target: $@"
	$(ECHO)$(MKDIR) $(OUTPUT_DIR)
	$(ECHO)$(CC) $(LDFLAGS) ${filter-out %.a,$^} ${filter %.a,$^} $(LIBS) -o $(OUTPUT_DIR)/$@

clean:
ifeq ($(filter $(MAKECMDGOALS),all debug release),)
	rm -rf $(CLEAN)
	$(RMDIRS) ./debug/
	$(RMDIRS) ./release/
	$(RMDIRS) $(OBJ_DIR)
	$(RMFILES) $(TARGET)
	$(RMFILES) $(TARGET).exe
	$(RMFILES) $(TARGET).S
endif
